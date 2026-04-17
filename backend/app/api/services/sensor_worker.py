import queue
import threading
import os
import logging
from datetime import datetime, timezone, timedelta

from api.models.request_model import SensorData
from api.services.camera_service import CameraService
from api.services.email_service import EmailService
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
        self._last_capture_time: dict[str, datetime] = {}  # Track last capture time per device
        self._capture_lock = threading.Lock()  # Thread-safe access to capture timing
        self._last_email_time: dict[str, datetime] = {}  # Track last email sent time per device
        self._email_lock = threading.Lock()  # Thread-safe access to email timing
        self.camera_service = CameraService()
        self.email_service = EmailService()
        self.firebase_service = FirebaseService()
        self.device_id = os.getenv("FIREBASE_DEVICE_ID", "esp32")
        self.firebase_input_enabled = (
            os.getenv("FIREBASE_INPUT_ENABLED", "true").lower() == "true"
        )
        self.firebase_input_path = os.getenv("FIREBASE_INPUT_PATH", self.device_id)
        self.firebase_poll_seconds = float(os.getenv("FIREBASE_INPUT_POLL_SECONDS", "1.0"))
        self.warning_capture_delay_seconds = float(
            os.getenv("WARNING_CAPTURE_DELAY_SECONDS", "120")  # 2 minutes default
        )
        self.warning_email_delay_seconds = float(
            os.getenv("WARNING_EMAIL_DELAY_SECONDS", "86400")  # 24 hours (1 day) default
        )
        logger.info(
            "SensorWorker initialized: firebase_enabled=%s input_enabled=%s input_path=%s device_id=%s poll_seconds=%s warning_capture_delay=%s warning_email_delay=%s",
            self.firebase_service.enabled,
            self.firebase_input_enabled,
            self.firebase_input_path,
            self.device_id,
            self.firebase_poll_seconds,
            self.warning_capture_delay_seconds,
            self.warning_email_delay_seconds,
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

    def _should_capture(self, device_id: str, severity: str) -> bool:
        """
        Determine if image capture should proceed based on severity level and timing.
        - DANGER: always capture (no delay)
        - WARNING: capture only if 2 minutes have passed since last capture
        - NORMAL: never capture
        """
        if severity == "danger":
            # Danger level: always capture immediately
            return True
        
        if severity != "warning":
            # Only capture for warning and danger
            return False
        
        # Warning level: check if enough time has passed
        with self._capture_lock:
            now = datetime.now(timezone.utc)
            last_capture = self._last_capture_time.get(device_id)
            
            if last_capture is None:
                # First capture for this device
                self._last_capture_time[device_id] = now
                logger.info(
                    "First capture for device: device_id=%s severity=%s",
                    device_id,
                    severity,
                )
                return True
            
            time_since_last = (now - last_capture).total_seconds()
            if time_since_last >= self.warning_capture_delay_seconds:
                # Enough time has passed
                self._last_capture_time[device_id] = now
                logger.info(
                    "Capture allowed: device_id=%s severity=%s time_since_last=%.1fs delay=%.1fs",
                    device_id,
                    severity,
                    time_since_last,
                    self.warning_capture_delay_seconds,
                )
                return True
            else:
                # Not enough time has passed
                logger.info(
                    "Capture skipped (delay not met): device_id=%s severity=%s time_since_last=%.1fs delay=%.1fs",
                    device_id,
                    severity,
                    time_since_last,
                    self.warning_capture_delay_seconds,
                )
                return False

    def _should_send_email(self, device_id: str, severity: str) -> bool:
        """
        Determine if email should be sent based on severity level and timing.
        - DANGER: always send (no delay)
        - WARNING: send only if 24 hours have passed since last email
        - NORMAL: never send
        """
        if severity == "danger":
            # Danger level: always send immediately
            return True
        
        if severity != "warning":
            # Only send email for warning and danger
            return False
        
        # Warning level: check if enough time has passed
        with self._email_lock:
            now = datetime.now(timezone.utc)
            last_email = self._last_email_time.get(device_id)
            
            if last_email is None:
                # First email for this device
                self._last_email_time[device_id] = now
                logger.info(
                    "First email for device: device_id=%s severity=%s",
                    device_id,
                    severity,
                )
                return True
            
            time_since_last = (now - last_email).total_seconds()
            if time_since_last >= self.warning_email_delay_seconds:
                # Enough time has passed
                self._last_email_time[device_id] = now
                logger.info(
                    "Email allowed: device_id=%s severity=%s time_since_last=%.1fs delay=%.1fs",
                    device_id,
                    severity,
                    time_since_last,
                    self.warning_email_delay_seconds,
                )
                return True
            else:
                # Not enough time has passed
                logger.info(
                    "Email skipped (delay not met): device_id=%s severity=%s time_since_last=%.1fs delay=%.1fs",
                    device_id,
                    severity,
                    time_since_last,
                    self.warning_email_delay_seconds,
                )
                return False

    def _handle_prediction(self, device_id: str, data: SensorData, prediction: str) -> None:
        severity = prediction.lower()
        
        # Only capture image for warning/danger predictions, respecting delay logic
        image_base64 = None
        if severity in {"warning", "danger"}:
            if self._should_capture(device_id, severity):
                image_path = self.camera_service.capture_image(device_id=device_id)
                if image_path:
                    logger.info("Camera image captured: %s", image_path)
                    image_base64 = self.firebase_service.save_image_base64(
                        local_path=image_path,
                        device_id=device_id,
                    )
                else:
                    logger.info("Camera disabled or image unavailable; continuing without image")
            else:
                logger.debug("Capture skipped due to delay policy: device_id=%s severity=%s", device_id, severity)

        event = {
            "device_id": device_id,
            "prediction": prediction,
            "temperature": data.temperature,
            "humidity": data.humidity,
            "gas": data.gas,
        }
        if image_base64:
            event["timestamp"] = datetime.now(timezone.utc).isoformat()
            event["image_base64"] = image_base64
        self.firebase_service.save_alert_event(event)
        
        # Send email only if severity allows it (respecting delay logic)
        if severity in {"warning", "danger"}:
            if self._should_send_email(device_id, severity):
                self.email_service.send_alert_email(
                    device_id=device_id,
                    prediction=prediction,
                    temperature=data.temperature,
                    humidity=data.humidity,
                    gas=data.gas,
                )
            else:
                logger.debug("Email skipped due to delay policy: device_id=%s severity=%s", device_id, severity)
        
        logger.info("Alert event written to Firebase: device_id=%s prediction=%s", device_id, prediction)
