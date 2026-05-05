import logging
import re

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import settings

logger = logging.getLogger(__name__)

# BR phone: (XX)9XXXX-XXXX or XX9XXXXXXXX
_BR_PHONE_RE = re.compile(r"^(?:\+?55)?\s*\(?([1-9][0-9])\)?\s*(9[0-9]{8})$")


class WhatsAppAdapter:
    """Sends appointment reminders via WhatsApp Business API (Meta Cloud API).
    Template must be pre-approved; parameters contain NO clinical data per LGPD.
    """

    def __init__(self) -> None:
        self._api_url = settings.whatsapp_api_url
        self._token = settings.whatsapp_api_token
        self._phone_number_id = settings.whatsapp_phone_number_id
        self._template_name = settings.whatsapp_template_name
        self._client = httpx.AsyncClient(timeout=30.0)

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=10))
    async def send_reminder(
        self,
        to_number: str,
        patient_name: str,
        appointment_date: str,
        appointment_time: str,
        appointment_type: str,
    ) -> str:
        """Returns message ID on success. Raises on failure.
        Template parameters: name, date, time, type (NO clinical data).
        """
        if not self._token or not self._phone_number_id:
            raise RuntimeError("WhatsApp credentials not configured.")

        validation_error = self._validate_number(to_number)
        if validation_error:
            raise ValueError(f"Invalid phone number: {validation_error}")

        normalized = self._normalize_number(to_number)
        payload = {
            "messaging_product": "whatsapp",
            "to": normalized,
            "type": "template",
            "template": {
                "name": self._template_name,
                "language": {"code": "pt_BR"},
                "components": [
                    {
                        "type": "body",
                        "parameters": [
                            {"type": "text", "text": patient_name},
                            {"type": "text", "text": appointment_date},
                            {"type": "text", "text": appointment_time},
                            {"type": "text", "text": appointment_type},
                        ],
                    }
                ],
            },
        }

        resp = await self._client.post(
            f"{self._api_url}/{self._phone_number_id}/messages",
            json=payload,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
            },
        )
        resp.raise_for_status()
        message_id: str = resp.json()["messages"][0]["id"]
        logger.info("WhatsApp sent to %s, msg_id=%s", normalized[-4:], message_id)
        return message_id

    def _normalize_number(self, number: str) -> str:
        digits = "".join(c for c in number if c.isdigit())
        if not digits.startswith("55"):
            digits = "55" + digits
        return digits

    def _validate_number(self, number: str) -> str | None:
        """Validates BR phone format. Returns error message or None."""
        digits = "".join(c for c in number if c.isdigit())
        if digits.startswith("55"):
            digits = digits[2:]
        m = _BR_PHONE_RE.match(digits) or _BR_PHONE_RE.match(f"({digits[:2]}){digits[2:]}")
        if not m:
            return (
                f"Formato inválido: '{number}'. "
                "Esperado: (XX)9XXXX-XXXX com DDD válido e 9 dígito."
            )
        return None

    async def close(self) -> None:
        await self._client.aclose()
