use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use crate::config::Config;

pub const TOKEN_TYPE_ACCESS: &str = "access";
pub const TOKEN_TYPE_REFRESH: &str = "refresh";

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    #[serde(rename = "type")]
    pub token_type: String,
    pub iat: i64,
    pub exp: i64,
}

pub fn create_access_token(user_id: i64, config: &Config) -> Result<String, String> {
    create_token(
        user_id,
        TOKEN_TYPE_ACCESS,
        Duration::minutes(config.access_token_expire_minutes),
        config,
    )
}

pub fn create_refresh_token(user_id: i64, config: &Config) -> Result<String, String> {
    create_token(
        user_id,
        TOKEN_TYPE_REFRESH,
        Duration::days(config.refresh_token_expire_days),
        config,
    )
}

fn create_token(
    user_id: i64,
    token_type: &str,
    expires_delta: Duration,
    config: &Config,
) -> Result<String, String> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id.to_string(),
        token_type: token_type.to_string(),
        iat: now.timestamp(),
        exp: (now + expires_delta).timestamp(),
    };

    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(config.jwt_secret_key.as_bytes()),
    )
    .map_err(|e| format!("Failed to create token: {e}"))
}

pub fn verify_token(token: &str, expected_type: &str, config: &Config) -> Result<Claims, String> {
    let mut validation = Validation::default();
    validation.set_required_spec_claims(&["exp", "sub"]);

    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(config.jwt_secret_key.as_bytes()),
        &validation,
    )
    .map_err(|e| match e.kind() {
        jsonwebtoken::errors::ErrorKind::ExpiredSignature => "Token has expired".to_string(),
        _ => format!("Invalid token: {e}"),
    })?;

    if token_data.claims.token_type != expected_type {
        return Err(format!(
            "Invalid token type: expected {expected_type}"
        ));
    }

    Ok(token_data.claims)
}

pub fn decode_jwt_payload(token: &str) -> Option<serde_json::Value> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() < 2 {
        return None;
    }
    let payload_bytes = URL_SAFE_NO_PAD.decode(parts[1]).ok()?;
    serde_json::from_slice(&payload_bytes).ok()
}
