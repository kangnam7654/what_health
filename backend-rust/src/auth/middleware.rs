use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use sqlx::SqlitePool;

use crate::auth::jwt::{verify_token, TOKEN_TYPE_ACCESS};
use crate::config::Config;
use crate::error::AppError;
use crate::models::User;

pub struct AuthUser(pub User);

impl<S: Send + Sync> FromRequestParts<S> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let auth_header = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| AppError::Unauthorized("Missing Authorization header".into()))?;

        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or_else(|| AppError::Unauthorized("Invalid Authorization header format".into()))?;

        let config = parts
            .extensions
            .get::<Config>()
            .ok_or_else(|| AppError::Internal("Config not found".into()))?;

        let claims = verify_token(token, TOKEN_TYPE_ACCESS, config)
            .map_err(|e| AppError::Unauthorized(e))?;

        let user_id: i64 = claims
            .sub
            .parse()
            .map_err(|_| AppError::Unauthorized("Invalid user ID in token".into()))?;

        let pool = parts
            .extensions
            .get::<SqlitePool>()
            .ok_or_else(|| AppError::Internal("Database pool not found".into()))?;

        let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = ?")
            .bind(user_id)
            .fetch_optional(pool)
            .await
            .map_err(|e| AppError::Internal(format!("Database error: {e}")))?
            .ok_or_else(|| AppError::Unauthorized("User not found".into()))?;

        Ok(AuthUser(user))
    }
}
