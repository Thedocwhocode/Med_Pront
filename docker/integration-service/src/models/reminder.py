import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional


class Channel(str, Enum):
    SMS = "sms"
    EMAIL = "email"
    WHATSAPP = "whatsapp"


class ReminderStatus(str, Enum):
    PENDING = "pending"
    SENT = "sent"
    FAILED = "failed"
    FAILED_PERMANENT = "failed_permanent"
    REVOKED = "revoked"


@dataclass
class Reminder:
    appointment_id: str
    patient_pid: str
    channel: Channel
    consent_verified: bool
    status: ReminderStatus = ReminderStatus.PENDING
    sent_at: Optional[datetime] = None
    content_hash: Optional[str] = None
    error_message: Optional[str] = None
    attempt_count: int = 0
    created_at: datetime = field(default_factory=datetime.utcnow)

    def compute_content_hash(self, content: str) -> str:
        return hashlib.sha256(content.encode()).hexdigest()

    def mark_sent(self, content: str) -> None:
        self.status = ReminderStatus.SENT
        self.sent_at = datetime.now(timezone.utc)
        self.content_hash = self.compute_content_hash(content)
        self.attempt_count += 1

    def mark_failed(self, error: str) -> None:
        self.status = ReminderStatus.FAILED
        self.error_message = error
        self.attempt_count += 1

    def mark_permanent_failure(self, error: str) -> None:
        self.status = ReminderStatus.FAILED_PERMANENT
        self.error_message = error

    def revoke(self) -> None:
        self.status = ReminderStatus.REVOKED
