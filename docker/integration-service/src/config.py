from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # OpenEMR API
    openemr_api_url: str
    openemr_client_id: str
    openemr_client_secret: str

    # Twilio (SMS)
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_from_number: str = ""

    # WhatsApp Business API
    whatsapp_api_url: str = "https://graph.facebook.com/v19.0"
    whatsapp_api_token: str = ""
    whatsapp_phone_number_id: str = ""
    whatsapp_template_name: str = "appointment_reminder"

    # SMTP
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""

    # Service security
    integration_secret_key: str

    @field_validator("openemr_api_url")
    @classmethod
    def openemr_url_not_empty(cls, v: str) -> str:
        if not v:
            raise ValueError("OPENEMR_API_URL is required")
        return v.rstrip("/")


settings = Settings()
