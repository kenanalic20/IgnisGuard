import os
import base64
import logging

try:
    import firebase_admin
    from firebase_admin import credentials, db
except ImportError:  # pragma: no cover - optional dependency for local development
    firebase_admin = None
    credentials = None
    db = None


logger = logging.getLogger(__name__)


class FirebaseService:
    def __init__(self):
        self.enabled = os.getenv("FIREBASE_ENABLED", "false").lower() == "true"
        self.root_path = os.getenv("FIREBASE_ROOT_PATH", "/")
        logger.info(
            "FirebaseService initializing: enabled=%s root_path=%s",
            self.enabled,
            self.root_path,
        )

        if not self.enabled:
            logger.info("FirebaseService disabled by FIREBASE_ENABLED")
            return

        if firebase_admin is None:
            raise RuntimeError(
                "FIREBASE_ENABLED=true but firebase-admin is not installed. "
                "Install with: pip install firebase-admin"
            )

        if not firebase_admin._apps:
            cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
            db_url = os.getenv("FIREBASE_DATABASE_URL")

            if not cred_path or not db_url:
                raise RuntimeError(
                    "Missing Firebase config. Required: FIREBASE_CREDENTIALS_PATH, "
                    "FIREBASE_DATABASE_URL"
                )

            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(
                cred,
                {
                    "databaseURL": db_url,
                },
            )
            logger.info("Firebase app initialized with database URL")
        else:
            logger.info("Firebase app already initialized")

    def save_image_base64(self, local_path: str, device_id: str) -> str | None:
        if not self.enabled:
            logger.debug("Skipping image encode because Firebase is disabled")
            return None

        with open(local_path, "rb") as image_file:
            encoded = base64.b64encode(image_file.read()).decode("utf-8")

        # Store as a browser-ready data URL.
        logger.info("Image encoded to base64 data URL: device_id=%s", device_id)
        return f"data:image/jpeg;base64,{encoded}"

    def read_sensor_data(self, input_path: str) -> dict | None:
        if not self.enabled:
            logger.debug("Skipping Firebase read because Firebase is disabled")
            return None

        snapshot = db.reference(input_path).get()
        if isinstance(snapshot, dict):
            logger.debug("Read sensor snapshot from Firebase path: %s", input_path)
            return snapshot
        logger.debug("Firebase path did not contain dict payload: path=%s value_type=%s", input_path, type(snapshot).__name__)
        return None

    def save_alert_event(self, event: dict) -> None:
        if not self.enabled:
            logger.debug("Skipping Firebase write because Firebase is disabled")
            return

        device_id = event.get("device_id", "esp32")
        
        # Read previous image and timestamp from Firebase
        previous_data = db.reference(self.root_path).get()
        previous_image = ""
        previous_timestamp = ""
        if isinstance(previous_data, dict):
            previous_image = previous_data.get("image", "")
            previous_timestamp = previous_data.get("timestamp", "")
        
        # Use new values if provided, otherwise keep previous values
        image_base64 = event.get("image_base64") if event.get("image_base64") else previous_image
        timestamp = event.get("timestamp") if event.get("timestamp") else previous_timestamp
        
        payload = {
            "alerts": event.get("prediction", ""),
            device_id: {
                "temperature": event.get("temperature"),
                "humidity": event.get("humidity"),
                "gas": event.get("gas"),
            },
            "image": image_base64,
            "timestamp": timestamp,
        }

        db.reference(self.root_path).update(payload)
        logger.info("Firebase snapshot updated at root path: %s", self.root_path)
