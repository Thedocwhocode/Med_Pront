import logging
import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from ..config import settings

logger = logging.getLogger(__name__)

# Reminder email body — NO clinical data per LGPD
_BODY_TEMPLATE = """\
Olá, {patient_name}.

Este é um lembrete da sua consulta:

  Data:  {appointment_date}
  Hora:  {appointment_time}
  Tipo:  {appointment_type}

Para cancelar ou reagendar, entre em contato com a clínica.

Este email é automático, não responda.
"""


class EmailAdapter:
    def __init__(self) -> None:
        self._host = settings.smtp_host
        self._port = settings.smtp_port
        self._user = settings.smtp_user
        self._password = settings.smtp_password
        self._from = settings.smtp_from

    def send_reminder(
        self,
        to_email: str,
        patient_name: str,
        appointment_date: str,
        appointment_time: str,
        appointment_type: str,
    ) -> None:
        """Sends appointment reminder. Raises on failure.
        Content contains NO clinical data (no diagnosis, CID, medications).
        """
        if not self._host:
            raise RuntimeError("SMTP not configured.")

        body = _BODY_TEMPLATE.format(
            patient_name=patient_name,
            appointment_date=appointment_date,
            appointment_time=appointment_time,
            appointment_type=appointment_type,
        )

        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"Lembrete de consulta — {appointment_date} às {appointment_time}"
        msg["From"] = self._from
        msg["To"] = to_email
        msg.attach(MIMEText(body, "plain", "utf-8"))

        context = ssl.create_default_context()
        with smtplib.SMTP(self._host, self._port) as smtp:
            smtp.ehlo()
            smtp.starttls(context=context)
            smtp.login(self._user, self._password)
            smtp.sendmail(self._from, to_email, msg.as_string())

        logger.info("Email sent to %s", to_email[-6:])
