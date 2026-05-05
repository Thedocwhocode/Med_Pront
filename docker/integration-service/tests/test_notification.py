"""Unit tests for NotificationService — T065."""
import asyncio
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock

import pytest

from src.models.reminder import Channel, Reminder, ReminderStatus
from src.services.notification import MAX_ATTEMPTS, NotificationService, _reminders, _retry_queue


@pytest.fixture(autouse=True)
def clear_state():
    _reminders.clear()
    _retry_queue.clear()
    yield
    _reminders.clear()
    _retry_queue.clear()


def make_appointment(pid="1", eid="appt-1", cat="Consulta Presencial"):
    now = datetime.now(timezone.utc)
    return {
        "pc_pid": pid,
        "pc_eid": eid,
        "pc_eventDate": now.strftime("%Y-%m-%d"),
        "pc_startTime": now.strftime("%H:%M:%S"),
        "pc_catname": cat,
    }


def make_consent(email=True, whatsapp=True):
    return {
        "channels": {
            Channel.SMS: False,
            Channel.EMAIL: email,
            Channel.WHATSAPP: whatsapp,
        },
        "email": "patient@example.com",
        "phone_cell": "11999999999",
        "fname": "Maria",
        "lname": "Souza",
    }


class TestDispatch:
    def test_sends_whatsapp_on_success(self):
        svc = NotificationService.__new__(NotificationService)
        svc._whatsapp = MagicMock()
        svc._whatsapp.send_reminder = AsyncMock(return_value="msg-id-123")
        svc._email = MagicMock()
        svc._oe = MagicMock()
        svc._consent = MagicMock()

        reminder = Reminder(
            appointment_id="appt-1",
            patient_pid="1",
            channel=Channel.WHATSAPP,
            consent_verified=True,
        )
        result = asyncio.run(
            svc._dispatch(reminder, "Maria Souza", "11999999999", "2026-05-05", "10:00", "Consulta")
        )
        assert result is True
        assert reminder.status == ReminderStatus.SENT
        assert reminder.content_hash is not None

    def test_retries_on_failure(self):
        svc = NotificationService.__new__(NotificationService)
        svc._whatsapp = MagicMock()
        svc._whatsapp.send_reminder = AsyncMock(side_effect=RuntimeError("Network error"))
        svc._email = MagicMock()
        svc._oe = MagicMock()
        svc._consent = MagicMock()

        reminder = Reminder(
            appointment_id="appt-2",
            patient_pid="1",
            channel=Channel.WHATSAPP,
            consent_verified=True,
        )
        result = asyncio.run(
            svc._dispatch(reminder, "Maria Souza", "11999999999", "2026-05-05", "10:00", "Consulta")
        )
        assert result is False
        assert reminder.status == ReminderStatus.FAILED
        assert reminder.attempt_count == 1
        assert len(_retry_queue) == 1

    def test_permanent_failure_after_max_attempts(self):
        svc = NotificationService.__new__(NotificationService)
        svc._whatsapp = MagicMock()
        svc._whatsapp.send_reminder = AsyncMock(side_effect=RuntimeError("Fail"))
        svc._email = MagicMock()
        svc._email.send_reminder = MagicMock()
        svc._oe = MagicMock()
        svc._consent = MagicMock()

        reminder = Reminder(
            appointment_id="appt-3",
            patient_pid="1",
            channel=Channel.WHATSAPP,
            consent_verified=True,
            attempt_count=MAX_ATTEMPTS - 1,
        )
        result = asyncio.run(
            svc._dispatch(reminder, "Maria", "11999999999", "2026-05-05", "10:00", "Consulta")
        )
        assert result is False
        assert reminder.status == ReminderStatus.FAILED_PERMANENT
        assert len(_retry_queue) == 0


class TestReminderModel:
    def test_mark_sent_sets_hash(self):
        r = Reminder("a1", "p1", Channel.EMAIL, True)
        r.mark_sent("Maria|2026-05-05|10:00|Consulta|email")
        assert r.status == ReminderStatus.SENT
        assert r.content_hash is not None
        assert len(r.content_hash) == 64

    def test_mark_failed_increments_attempts(self):
        r = Reminder("a1", "p1", Channel.EMAIL, True)
        r.mark_failed("timeout")
        assert r.attempt_count == 1
        assert r.status == ReminderStatus.FAILED

    def test_revoke(self):
        r = Reminder("a1", "p1", Channel.SMS, True)
        r.revoke()
        assert r.status == ReminderStatus.REVOKED
