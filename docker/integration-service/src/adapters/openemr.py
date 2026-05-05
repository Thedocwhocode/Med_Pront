import logging
from datetime import datetime, timedelta
from typing import Any

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import settings

logger = logging.getLogger(__name__)

_token_cache: dict[str, Any] = {}


class OpenEMRClient:
    def __init__(self) -> None:
        self._base_url = settings.openemr_api_url
        self._client = httpx.AsyncClient(timeout=30.0)

    async def _get_token(self) -> str:
        now = datetime.utcnow()
        if _token_cache.get("expires_at", now) > now:
            return _token_cache["access_token"]

        resp = await self._client.post(
            f"{self._base_url}/oauth2/default/token",
            data={
                "grant_type": "client_credentials",
                "client_id": settings.openemr_client_id,
                "client_secret": settings.openemr_client_secret,
                "scope": "openid api:oemr api:fhir",
            },
        )
        resp.raise_for_status()
        data = resp.json()
        _token_cache["access_token"] = data["access_token"]
        _token_cache["expires_at"] = now + timedelta(seconds=data.get("expires_in", 3600) - 60)
        return data["access_token"]

    def _auth_headers(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8))
    async def get_appointments_window(self, hours_ahead: int = 24) -> list[dict]:
        token = await self._get_token()
        now = datetime.utcnow()
        date_from = now.strftime("%Y-%m-%d")
        date_to = (now + timedelta(hours=hours_ahead + 1)).strftime("%Y-%m-%d")

        resp = await self._client.get(
            f"{self._base_url}/api/appointment",
            params={"date_from": date_from, "date_to": date_to},
            headers=self._auth_headers(token),
        )
        resp.raise_for_status()
        appointments = resp.json().get("data", [])

        target_min = now + timedelta(hours=hours_ahead - 1)
        target_max = now + timedelta(hours=hours_ahead + 1)

        return [
            a for a in appointments
            if self._in_window(a.get("pc_startTime", ""), a.get("pc_eventDate", ""), target_min, target_max)
        ]

    def _in_window(self, time_str: str, date_str: str, min_dt: datetime, max_dt: datetime) -> bool:
        try:
            appt_dt = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M:%S")
            return min_dt <= appt_dt <= max_dt
        except ValueError:
            return False

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8))
    async def get_patient(self, pid: str) -> dict:
        token = await self._get_token()
        resp = await self._client.get(
            f"{self._base_url}/api/patient/{pid}",
            headers=self._auth_headers(token),
        )
        resp.raise_for_status()
        return resp.json().get("data", {})

    async def close(self) -> None:
        await self._client.aclose()
