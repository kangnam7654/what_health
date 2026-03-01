use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret_key: String,
    pub jwt_algorithm: String,
    pub access_token_expire_minutes: i64,
    pub refresh_token_expire_days: i64,
    pub openai_api_key: String,
    pub gemini_api_key: String,
    pub codex_default_model: String,
    pub google_client_id: String,
    pub google_client_secret: String,
    pub apple_team_id: String,
    pub apple_key_id: String,
    pub apple_bundle_id: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            database_url: env::var("DATABASE_URL")
                .unwrap_or_else(|_| "sqlite:///data/app.db?mode=rwc".into()),
            jwt_secret_key: env::var("JWT_SECRET_KEY")
                .unwrap_or_else(|_| "change-me-in-production".into()),
            jwt_algorithm: env::var("JWT_ALGORITHM").unwrap_or_else(|_| "HS256".into()),
            access_token_expire_minutes: env::var("ACCESS_TOKEN_EXPIRE_MINUTES")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(30),
            refresh_token_expire_days: env::var("REFRESH_TOKEN_EXPIRE_DAYS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(7),
            openai_api_key: env::var("OPENAI_API_KEY").unwrap_or_default(),
            gemini_api_key: env::var("GEMINI_API_KEY").unwrap_or_default(),
            codex_default_model: env::var("CODEX_DEFAULT_MODEL")
                .unwrap_or_else(|_| "gpt-5.3-codex".into()),
            google_client_id: env::var("GOOGLE_CLIENT_ID").unwrap_or_default(),
            google_client_secret: env::var("GOOGLE_CLIENT_SECRET").unwrap_or_default(),
            apple_team_id: env::var("APPLE_TEAM_ID").unwrap_or_default(),
            apple_key_id: env::var("APPLE_KEY_ID").unwrap_or_default(),
            apple_bundle_id: env::var("APPLE_BUNDLE_ID")
                .unwrap_or_else(|_| "com.whathealth.app".into()),
        }
    }
}
