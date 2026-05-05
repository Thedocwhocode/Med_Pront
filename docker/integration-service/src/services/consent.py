import logging
from datetime import datetime, timezone
from typing import Optional

from ..adapters.openemr import OpenEMRClient
from ..models.reminder import Channel

logger = logging.getLogger(__name__)

# Tracks revoked consent per patient in-memory.
# Production systems should persist this to a database.
_revocations: dict[str, set[str]] = {}


class ConsentService:
    """T046 — Verifies per-channel consent before sending reminders.
    T058 — Supports immediate consent revocation.
    """

    def __init__(self, openemr: Optional[OpenEMRClient] = None) -> None:
        self._oe = openemr or OpenEMRClient()

    async def get_consent(self, patient_pid: str) -> dict:
        patient = await self._oe.get_patient(patient_pid)
        revoked = _revocations.get(patient_pid, set())
        return {
            "patient_pid": patient_pid,
            "channels": {
                Channel.SMS: bool(patient.get("hipaa_allowsms")) and Channel.SMS not in revoked,
                Channel.EMAIL: bool(patient.get("hipaa_allowemail")) and Channel.EMAIL not in revoked,
                Channel.WHATSAPP: bool(patient.get("allow_whatsapp")) and Channel.WHATSAPP not in revoked,
            },
            "phone_cell": patient.get("phone_cell", ""),
            "email": patient.get("email", ""),
            "fname": patient.get("fname", ""),
            "lname": patient.get("lname", ""),
        }

    def is_channel_allowed(self, consent_data: dict, channel: Channel) -> bool:
        return bool(consent_data.get("channels", {}).get(channel, False))

    async def revoke(self, patient_pid: str, channel: Optional[Channel] = None) -> dict:
        """T058 — Immediate revocation. channel=None revokes all channels."""
        if patient_pid not in _revocations:
            _revocations[patient_pid] = set()

        if channel is None:
            _revocations[patient_pid] = {Channel.SMS, Channel.EMAIL, Channel.WHATSAPP}
            revoked = ["all"]
        else:
            _revocations[patient_pid].add(channel)
            revoked = [channel.value]

        logger.info(
            "Consent revoked: patient=%s channels=%s at=%s",
            patient_pid,
            revoked,
            datetime.now(timezone.utc).isoformat(),
        )
        return {
            "patient_pid": patient_pid,
            "revoked": revoked,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
