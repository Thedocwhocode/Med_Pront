"""Unit tests for ConsentService — T065."""
import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from src.models.reminder import Channel
from src.services.consent import ConsentService, _revocations


@pytest.fixture(autouse=True)
def clear_revocations():
    _revocations.clear()
    yield
    _revocations.clear()


def make_patient(hipaa_sms=True, hipaa_email=True, allow_whatsapp=True):
    return {
        "hipaa_allowsms": hipaa_sms,
        "hipaa_allowemail": hipaa_email,
        "allow_whatsapp": allow_whatsapp,
        "email": "test@example.com",
        "phone_cell": "11999999999",
        "fname": "João",
        "lname": "Silva",
    }


@pytest.fixture
def mock_oe():
    oe = MagicMock()
    oe.get_patient = AsyncMock(return_value=make_patient())
    return oe


@pytest.fixture
def service(mock_oe):
    return ConsentService(openemr=mock_oe)


class TestGetConsent:
    def test_all_channels_allowed(self, service):
        result = asyncio.run(service.get_consent("123"))
        assert result["channels"][Channel.SMS] is True
        assert result["channels"][Channel.EMAIL] is True
        assert result["channels"][Channel.WHATSAPP] is True

    def test_no_sms_consent(self, mock_oe):
        mock_oe.get_patient = AsyncMock(return_value=make_patient(hipaa_sms=False))
        svc = ConsentService(openemr=mock_oe)
        result = asyncio.run(svc.get_consent("123"))
        assert result["channels"][Channel.SMS] is False
        assert result["channels"][Channel.EMAIL] is True

    def test_no_whatsapp_consent(self, mock_oe):
        mock_oe.get_patient = AsyncMock(return_value=make_patient(allow_whatsapp=False))
        svc = ConsentService(openemr=mock_oe)
        result = asyncio.run(svc.get_consent("123"))
        assert result["channels"][Channel.WHATSAPP] is False


class TestIsChannelAllowed:
    def test_allowed_channel(self, service):
        consent = asyncio.run(service.get_consent("123"))
        assert service.is_channel_allowed(consent, Channel.EMAIL) is True

    def test_disallowed_channel(self, mock_oe, service):
        mock_oe.get_patient = AsyncMock(return_value=make_patient(hipaa_email=False))
        consent = asyncio.run(service.get_consent("123"))
        assert service.is_channel_allowed(consent, Channel.EMAIL) is False


class TestRevocation:
    def test_revoke_single_channel(self, service):
        result = asyncio.run(service.revoke("456", Channel.WHATSAPP))
        assert "whatsapp" in result["revoked"]

        consent = asyncio.run(service.get_consent("456"))
        assert consent["channels"][Channel.WHATSAPP] is False
        assert consent["channels"][Channel.EMAIL] is True

    def test_revoke_all_channels(self, service):
        asyncio.run(service.revoke("789", None))
        consent = asyncio.run(service.get_consent("789"))
        assert all(v is False for v in consent["channels"].values())

    def test_revocation_is_immediate(self, service):
        asyncio.run(service.revoke("111", Channel.EMAIL))
        consent = asyncio.run(service.get_consent("111"))
        assert not service.is_channel_allowed(consent, Channel.EMAIL)
