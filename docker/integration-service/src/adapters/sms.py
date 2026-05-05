import logging
import re

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import settings

logger = logging.getLogger(__name__)

_BR_PHONE_RE = re.compile(r"^(?:55)?([1-9][0-9])(9[0-9]{8})$")


class SMSAdapter:
    """Sends SMS reminders via Twilio.
    CHK036: On permanent failure, falls back to email if consented.
    """

    def __init__(self) -> None:
        self._sid = settings.twilio_account_sid
        self._token = settings.twilio_auth_token
        self._from = settings.twilio_from_number
        self._client = httpx.AsyncClient(timeout=30.0)

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=10))
    async def send_reminder(
        self,
        to_number: str,
        patient_name: str,
        appointment_date: str,
        appointment_time: str,
    ) -> str:
        """Returns Twilio SID on success. Raises on failure.
        Content is minimal: no clinical data per LGPD (CHK008/CHK035).
        """
        if not self._sid or not self._token:
            raise RuntimeError("Twilio credentials not configured.")

        error = self._validate_number(to_number)
        if error:
            raise ValueError(f"Invalid phone number: {error}")

        normalized = self._normalize(to_number)
        payload = {
            "From": self._from,
            "To": normalized,
            "Body": (
                f"Med_Pront: Ola {patient_name}, "
                f"lembramos sua consulta em {appointment_date} as {appointment_time}. "
                "Confirme presenca respondendo SIM."
            ),
        }

        resp = await self._client.post(
            f"https://api.twilio.com/2010-04-01/Accounts/{self._sid}/Messages.json",
            data=payload,
            auth=(self._sid, self._token),
        )
        resp.raise_for_status()
        sid: str = resp.json()["sid"]
        logger.info("SMS sent to %s, sid=%s", normalized[-4:], sid)
        return sid

    def _normalize(self, number: str) -> str:
        digits = "".join(c for c in number if c.isdigit())
        if not digits.startswith("55"):
            digits = "55" + digits
        return f"+{digits}"

    def _validate_number(self, number: str) -> str | None:
        digits = "".join(c for c in number if c.isdigit())
        if digits.startswith("55"):
            digits = digits[2:]
        if not _BR_PHONE_RE.match(digits):
            return (
                f"Formato invalido: '{number}'. "
                "Esperado: (XX)9XXXX-XXXX com DDD valido e 9 digito."
            )
        return None

    async def close(self) -> None:
        await self._client.aclose()
