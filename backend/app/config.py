from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    database_url: str = "sqlite+aiosqlite:///./app.db"

    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7

    openai_api_key: str = ""
    gemini_api_key: str = ""
    codex_default_model: str = "codex-mini-latest"

    google_client_id: str = ""
    google_client_secret: str = ""

    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_bundle_id: str = "com.exerciseplan.app"


settings = Settings()
