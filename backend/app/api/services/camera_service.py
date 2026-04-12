import os
from datetime import datetime, timezone
from pathlib import Path

try:
    import cv2
except ImportError:  # pragma: no cover - optional dependency for environments without camera
    cv2 = None


class CameraService:
    def __init__(self):
        self.enabled = os.getenv("CAMERA_ENABLED", "false").lower() == "true"
        self.camera_index = int(os.getenv("CAMERA_INDEX", "0"))
        self.output_dir = Path(os.getenv("CAMERA_OUTPUT_DIR", "./captures"))

    def capture_image(self, device_id: str) -> str | None:
        if not self.enabled:
            return None

        if cv2 is None:
            raise RuntimeError(
                "CAMERA_ENABLED=true but opencv-python is not installed. "
                "Install with: pip install opencv-python"
            )

        self.output_dir.mkdir(parents=True, exist_ok=True)
        file_name = (
            f"{device_id}_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.jpg"
        )
        image_path = self.output_dir / file_name

        cam = cv2.VideoCapture(self.camera_index)
        ok, frame = cam.read()
        cam.release()

        if not ok:
            raise RuntimeError("Failed to capture image from camera")

        cv2.imwrite(str(image_path), frame)
        return str(image_path)
