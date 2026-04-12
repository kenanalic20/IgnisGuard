import queue
import threading
import os
import logging
from datetime import datetime, timezone

from api.models.request_model import SensorData
from api.services.camera_service import CameraService
from api.services.firebase_service import FirebaseService
from api.services.ml_service import predict


logger = logging.getLogger(__name__)


class SensorWorker:
    def __init__(self):
        self._queue: queue.Queue[tuple[str, SensorData]] = queue.Queue()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._firebase_thread: threading.Thread | None = None
        self._last_sensor_signature: tuple[float, float, float] | None = None
        self.camera_service = CameraService()
        self.firebase_service = FirebaseService()
        self.device_id = os.getenv("FIREBASE_DEVICE_ID", "esp32")
        self.firebase_input_enabled = (
            os.getenv("FIREBASE_INPUT_ENABLED", "true").lower() == "true"
        )
        self.firebase_input_path = os.getenv("FIREBASE_INPUT_PATH", self.device_id)
        self.firebase_poll_seconds = float(os.getenv("FIREBASE_INPUT_POLL_SECONDS", "1.0"))
        logger.info(
            "SensorWorker initialized: firebase_enabled=%s input_enabled=%s input_path=%s device_id=%s poll_seconds=%s",
            self.firebase_service.enabled,
            self.firebase_input_enabled,
            self.firebase_input_path,
            self.device_id,
            self.firebase_poll_seconds,
        )

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            logger.info("SensorWorker main thread already running")
            return

        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        logger.info("SensorWorker main thread started")

        if self.firebase_service.enabled and self.firebase_input_enabled:
            self._firebase_thread = threading.Thread(target=self._run_firebase_input, daemon=True)
            self._firebase_thread.start()
            logger.info("SensorWorker Firebase input thread started")
        else:
            logger.info(
                "SensorWorker Firebase input thread not started: firebase_enabled=%s input_enabled=%s",
                self.firebase_service.enabled,
                self.firebase_input_enabled,
            )

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=3)
        if self._firebase_thread:
            self._firebase_thread.join(timeout=3)
        logger.info("SensorWorker stopped")

    def enqueue(self, device_id: str, data: SensorData) -> None:
        self._queue.put((device_id, data))
        logger.info(
            "Queued sensor data: device_id=%s temp=%s humidity=%s gas=%s",
            device_id,
            data.temperature,
            data.humidity,
            data.gas,
        )

    def _run(self) -> None:
        while not self._stop_event.is_set():
            try:
                device_id, data = self._queue.get(timeout=0.5)
            except queue.Empty:
                continue

            try:
                prediction = predict(data)
                logger.info("Prediction computed: device_id=%s prediction=%s", device_id, prediction)
                self._handle_prediction(device_id=device_id, data=data, prediction=prediction)
            except Exception as exc:
                # Keep worker alive even if camera/Firebase/model processing fails for one event.
                logger.exception("Sensor worker processing failed: %s", exc)
            finally:
                self._queue.task_done()

    def _run_firebase_input(self) -> None:
        logger.info("Firebase input polling started")
        while not self._stop_event.is_set():
            try:
                raw = self.firebase_service.read_sensor_data(self.firebase_input_path)
                sensor_data = self._parse_sensor_data(raw)
                if sensor_data:
                    signature = (
                        sensor_data.temperature,
                        sensor_data.humidity,
                        sensor_data.gas,
                    )
                    if signature != self._last_sensor_signature:
                        self._last_sensor_signature = signature
                        logger.info("Firebase input changed; enqueuing new sample")
                        self.enqueue(device_id=self.device_id, data=sensor_data)
                    else:
                        logger.debug("Firebase input unchanged; skipping enqueue")
                else:
                    logger.debug("No valid sensor payload found at Firebase input path")
            except Exception as exc:
                logger.exception("Sensor worker Firebase input failed: %s", exc)

            self._stop_event.wait(timeout=self.firebase_poll_seconds)

    def _parse_sensor_data(self, raw: dict | None) -> SensorData | None:
        if not isinstance(raw, dict):
            return None

        temp = raw.get("temperature", raw.get("temp"))
        humidity = raw.get("humidity")
        gas = raw.get("gas")

        if temp is None or humidity is None or gas is None:
            logger.debug("Sensor payload missing required fields: %s", raw)
            return None

        try:
            return SensorData(
                temperature=float(temp),
                humidity=float(humidity),
                gas=float(gas),
            )
        except (TypeError, ValueError):
            logger.warning("Sensor payload has invalid numeric values: %s", raw)
            return None

    def _handle_prediction(self, device_id: str, data: SensorData, prediction: str) -> None:
        severity = prediction.lower()
        if severity not in {"warning", "danger"}:
            logger.info(
                "Prediction below alert threshold; Firebase write skipped: device_id=%s prediction=%s",
                device_id,
                prediction,
            )
            return

        image_base64 = None
        image_path = self.camera_service.capture_image(device_id=device_id)
        if image_path:
            logger.info("Camera image captured: %s", image_path)
            image_base64 = self.firebase_service.save_image_base64(
                local_path=image_path,
                device_id=device_id,
            )
        else:
            logger.info("Camera disabled or image unavailable; continuing without image")

        event = {
            "device_id": device_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "prediction": prediction,
            "temperature": data.temperature,
            "humidity": data.humidity,
            "gas": data.gas,
            "image_base64": image_base64,
        }
        self.firebase_service.save_alert_event(event)
        logger.info("Alert event written to Firebase: device_id=%s prediction=%s", device_id, prediction)
