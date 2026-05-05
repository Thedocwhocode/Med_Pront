import asyncio
import logging
from datetime import datetime, timedelta, timezone

from ..adapters.email import EmailAdapter
from ..adapters.openemr import OpenEMRClient
from ..adapters.sms import SMSAdapter
from ..adapters.whatsapp import WhatsAppAdapter
from ..models.reminder import Channel, Reminder, ReminderStatus
from .consent import ConsentService

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 3
RETRY_HOURS = 1
HOURS_AHEAD = 24

# In-memory store — replace with DB in production
_reminders: dict[str, Reminder] = {}
_retry_queue: list[tuple[datetime, Reminder]] = []


class NotificationService:
    """T049 — Scans appointments, verifies consent, sends reminders.
    T057 — Retry logic: 3 attempts, 1h apart; admin email on permanent failure.
    """

    def __init__(self) -> None:
        self._oe = OpenEMRClient()
        self._consent = ConsentService(self._oe)
        self._whatsapp = WhatsAppAdapter()
        self._sms = SMSAdapter()
        self._email = EmailAdapter()

    async def process_upcoming_reminders(self) -> dict:
        sent = failed = skipped = 0

        # Process retry queue first
        now = datetime.now(timezone.utc)
        due_retries = [(dt, r) for dt, r in _retry_queue if dt <= now]
        _retry_queue[:] = [(dt, r) for dt, r in _retry_queue if dt > now]

        for _, reminder in due_retries:
            if reminder.status == ReminderStatus.FAILED:
                result = await self._dispatch(reminder)
                if result:
                    sent += 1
                else:
                    failed += 1

        # Scan upcoming appointments
        appointments = await self._oe.get_appointments_window(hours_ahead=HOURS_AHEAD)
        logger.info("Found %d appointments in 24h window.", len(appointments))

        for appt in appointments:
            pid = str(appt.get("pc_pid", ""))
            appt_id = str(appt.get("pc_eid", appt.get("id", "")))

            consent = await self._consent.get_consent(pid)
            patient_name = f"{consent['fname']} {consent['lname']}".strip()
            appt_date = appt.get("pc_eventDate", "")
            appt_time = appt.get("pc_startTime", "")[:5]  # HH:MM
            appt_type = appt.get("pc_catname", "Consulta")

            for channel in [Channel.EMAIL, Channel.WHATSAPP, Channel.SMS]:
                if not self._consent.is_channel_allowed(consent, channel):
                    skipped += 1
                    continue

                key = f"{appt_id}:{channel}"
                if key in _reminders and _reminders[key].status in (
                    ReminderStatus.SENT, ReminderStatus.FAILED_PERMANENT
                ):
                    skipped += 1
                    continue

                reminder = _reminders.setdefault(
                    key,
                    Reminder(
                        appointment_id=appt_id,
                        patient_pid=pid,
                        channel=channel,
                        consent_verified=True,
                    ),
                )

                result = await self._dispatch(
                    reminder,
                    patient_name=patient_name,
                    to_address=consent["email"] if channel == Channel.EMAIL else consent["phone_cell"],
                    appt_date=appt_date,
                    appt_time=appt_time,
                    appt_type=appt_type,
                )
                if result:
                    sent += 1
                else:
                    failed += 1

        return {"sent": sent, "failed": failed, "skipped": skipped}

    async def send_single(self, appointment_id: str) -> dict:
        appointments = await self._oe.get_appointments_window(hours_ahead=48)
        appt = next((a for a in appointments if str(a.get("pc_eid", "")) == appointment_id), None)
        if not appt:
            return {"error": f"Appointment {appointment_id} not found in window."}

        pid = str(appt.get("pc_pid", ""))
        consent = await self._consent.get_consent(pid)
        patient_name = f"{consent['fname']} {consent['lname']}".strip()
        appt_date = appt.get("pc_eventDate", "")
        appt_time = appt.get("pc_startTime", "")[:5]
        appt_type = appt.get("pc_catname", "Consulta")

        results = {}
        for channel in [Channel.EMAIL, Channel.WHATSAPP, Channel.SMS]:
            if not self._consent.is_channel_allowed(consent, channel):
                results[channel] = "skipped (no consent)"
                continue
            reminder = Reminder(
                appointment_id=appointment_id,
                patient_pid=pid,
                channel=channel,
                consent_verified=True,
            )
            address = consent["email"] if channel == Channel.EMAIL else consent["phone_cell"]
            ok = await self._dispatch(reminder, patient_name, address, appt_date, appt_time, appt_type)
            results[channel] = "sent" if ok else "failed"

        return results

    async def _dispatch(
        self,
        reminder: Reminder,
        patient_name: str = "",
        to_address: str = "",
        appt_date: str = "",
        appt_time: str = "",
        appt_type: str = "",
    ) -> bool:
        try:
            if reminder.channel == Channel.WHATSAPP:
                await self._whatsapp.send_reminder(to_address, patient_name, appt_date, appt_time, appt_type)
            elif reminder.channel == Channel.SMS:
                await self._sms.send_reminder(to_address, patient_name, appt_date, appt_time)
            elif reminder.channel == Channel.EMAIL:
                content = f"{patient_name}|{appt_date}|{appt_time}|{appt_type}"
                await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self._email.send_reminder(to_address, patient_name, appt_date, appt_time, appt_type),
                )
            content = f"{patient_name}|{appt_date}|{appt_time}|{appt_type}|{reminder.channel}"
            reminder.mark_sent(content)
            return True

        except Exception as exc:
            logger.warning("Reminder dispatch failed: %s — %s", reminder.appointment_id, exc)
            reminder.mark_failed(str(exc))

            # T057: retry up to MAX_ATTEMPTS, then permanent failure + admin alert
            if reminder.attempt_count < MAX_ATTEMPTS:
                retry_at = datetime.now(timezone.utc) + timedelta(hours=RETRY_HOURS)
                _retry_queue.append((retry_at, reminder))
                logger.info("Queued retry %d/%d at %s", reminder.attempt_count, MAX_ATTEMPTS, retry_at)
            else:
                reminder.mark_permanent_failure(str(exc))
                logger.error(
                    "Permanent failure for appointment=%s channel=%s after %d attempts.",
                    reminder.appointment_id,
                    reminder.channel,
                    MAX_ATTEMPTS,
                )
                # CHK036: SMS-to-email fallback on permanent SMS failure
                if reminder.channel == Channel.SMS:
                    fallback_ok = await self._try_sms_fallback(
                        reminder, patient_name,
                        appt_date, appt_time, appt_type,
                    )
                    if fallback_ok:
                        return True
                self._notify_admin_failure(reminder)
            return False

    async def _try_sms_fallback(
        self,
        reminder: Reminder,
        patient_name: str,
        appt_date: str,
        appt_time: str,
        appt_type: str,
    ) -> bool:
        """CHK036: When SMS fails permanently, try email as secondary channel.
        First checks if patient has email consent and a valid email on file.
        """
        try:
            consent = await self._consent.get_consent(reminder.patient_pid)
            email = consent.get("email", "")
            if not email:
                logger.info("SMS fallback skipped: no email on file for pid=%s", reminder.patient_pid)
                return False
            if not self._consent.is_channel_allowed(consent, Channel.EMAIL):
                logger.info("SMS fallback skipped: no email consent for pid=%s", reminder.patient_pid)
                return False

            logger.info(
                "SMS fallback: sending email to %s for appointment=%s",
                email.split("@")[-1], reminder.appointment_id,
            )
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self._email.send_reminder(email, patient_name, appt_date, appt_time, appt_type),
            )
            content = f"{patient_name}|{appt_date}|{appt_time}|{appt_type}|sms_fallback_email"
            reminder.mark_sent(content)
            return True
        except Exception as exc:
            logger.error("SMS fallback to email also failed: %s", exc)
            self._notify_admin_failure(reminder)
            return False

    def _notify_admin_failure(self, reminder: Reminder) -> None:
        try:
            self._email.send_reminder(
                to_email=self._email._from,
                patient_name="[ADMIN ALERT]",
                appointment_date=reminder.appointment_id,
                appointment_time="N/A",
                appointment_type=f"Permanent reminder failure — channel={reminder.channel}",
            )
        except Exception:
            logger.error("Could not send admin failure notification.")
