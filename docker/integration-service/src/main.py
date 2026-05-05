import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from .config import settings  # noqa: F401 — validates env at startup

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Integration service starting up.")
    yield
    logger.info("Integration service shutting down.")


app = FastAPI(
    title="Med_Pront Integration Service",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
    lifespan=lifespan,
)


@app.get("/health", include_in_schema=False)
async def health() -> JSONResponse:
    return JSONResponse({"status": "ok"})


# --- Reminders (US5) ---

@app.get("/internal/reminders/check", include_in_schema=False)
async def reminders_check() -> JSONResponse:
    from .services.notification import NotificationService
    service = NotificationService()
    result = await service.process_upcoming_reminders()
    return JSONResponse(result)


@app.post("/internal/reminders/send", include_in_schema=False)
async def reminders_send(body: dict) -> JSONResponse:
    from .services.notification import NotificationService
    appointment_id = body.get("appointment_id")
    if not appointment_id:
        raise HTTPException(status_code=400, detail="appointment_id required")
    service = NotificationService()
    result = await service.send_single(appointment_id)
    return JSONResponse(result)


# --- Consent (US5) ---

@app.get("/internal/consent/{patient_pid}", include_in_schema=False)
async def consent_get(patient_pid: str) -> JSONResponse:
    from .services.consent import ConsentService
    service = ConsentService()
    consent = await service.get_consent(patient_pid)
    return JSONResponse(consent)
