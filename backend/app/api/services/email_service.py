import os
import logging
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail, Email, To, Content

logger = logging.getLogger(__name__)


class EmailService:
    def __init__(self):
        self.enabled = os.getenv("EMAIL_ENABLED", "false").lower() == "true"
        self.api_key = os.getenv("SENDGRID_API_KEY")
        self.from_email = os.getenv("EMAIL_FROM", "noreply@ignisguard.com")
        self.recipient_emails = os.getenv("EMAIL_RECIPIENTS", "").split(",")
        # Filter out empty strings
        self.recipient_emails = [email.strip() for email in self.recipient_emails if email.strip()]

        logger.info(
            "EmailService initializing: enabled=%s from=%s recipients=%d",
            self.enabled,
            self.from_email,
            len(self.recipient_emails),
        )

        if not self.enabled:
            logger.info("EmailService disabled by EMAIL_ENABLED")
            return

        if not self.api_key:
            raise RuntimeError(
                "EMAIL_ENABLED=true but SENDGRID_API_KEY is not set. "
                "Get free API key from https://sendgrid.com"
            )

        if not self.recipient_emails:
            raise RuntimeError(
                "EMAIL_ENABLED=true but EMAIL_RECIPIENTS is empty. "
                "Set EMAIL_RECIPIENTS as comma-separated list: user1@example.com,user2@example.com"
            )

    def send_alert_email(self, device_id: str, prediction: str, temperature: float, humidity: float, gas: float) -> bool:
        if not self.enabled:
            logger.debug("Skipping email send because EMAIL_ENABLED=false")
            return True

        subject = f"🚨 IgnisGuard Alert: {prediction.upper()} - {device_id}"
        
        body = f"""
Fire Detection Alert

Device: {device_id}
Prediction: {prediction}
Temperature: {temperature}°C
Humidity: {humidity}%
Gas Level: {gas}

Please check the IgnisGuard dashboard for more details.
        """.strip()

        try:
            sg = SendGridAPIClient(self.api_key)
            mail = Mail(
                from_email=self.from_email,
                to_emails=self.recipient_emails,
                subject=subject,
                plain_text_content=body,
            )
            response = sg.send(mail)
            logger.info(
                "Email sent successfully: device_id=%s prediction=%s status=%d",
                device_id,
                prediction,
                response.status_code,
            )
            return True
        except Exception as exc:
            logger.exception("Failed to send email alert: %s", exc)
            return False
