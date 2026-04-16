import os
import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

logger = logging.getLogger(__name__)


class EmailService:
    def __init__(self):
        self.enabled = os.getenv("EMAIL_ENABLED", "false").lower() == "true"
        self.gmail_user = os.getenv("GMAIL_USER")
        self.gmail_password = os.getenv("GMAIL_PASSWORD")  # App Password, not regular password
        self.recipient_emails = os.getenv("EMAIL_RECIPIENTS", "").split(",")
        # Filter out empty strings
        self.recipient_emails = [email.strip() for email in self.recipient_emails if email.strip()]

        logger.info(
            "EmailService initializing: enabled=%s from=%s recipients=%d",
            self.enabled,
            self.gmail_user,
            len(self.recipient_emails),
        )

        if not self.enabled:
            logger.info("EmailService disabled by EMAIL_ENABLED")
            return

        if not self.gmail_user or not self.gmail_password:
            raise RuntimeError(
                "EMAIL_ENABLED=true but GMAIL_USER or GMAIL_PASSWORD not set. "
                "Set GMAIL_USER=your-email@gmail.com and GMAIL_PASSWORD=your-app-password"
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
            # Create message
            msg = MIMEMultipart()
            msg["From"] = self.gmail_user
            msg["To"] = ", ".join(self.recipient_emails)
            msg["Subject"] = subject
            msg.attach(MIMEText(body, "plain"))

            # Send via Gmail SMTP
            server = smtplib.SMTP_SSL("smtp.gmail.com", 465)
            server.login(self.gmail_user, self.gmail_password)
            server.send_message(msg)
            server.quit()

            logger.info(
                "Email sent successfully via Gmail: device_id=%s prediction=%s",
                device_id,
                prediction,
            )
            return True
        except Exception as exc:
            logger.exception("Failed to send email alert: %s", exc)
            return False
