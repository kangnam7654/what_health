use axum::extract::{Extension, Query};
use axum::response::{IntoResponse, Redirect};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

use crate::auth::apple::verify_apple_identity_token;
use crate::auth::google::exchange_google_auth_code;
use crate::auth::jwt::{
    create_access_token, create_refresh_token, verify_token, TOKEN_TYPE_REFRESH,
};
use crate::auth::middleware::AuthUser;
use crate::auth::openai::exchange_chatgpt_auth_code;
use crate::config::Config;
use crate::error::AppError;

// ── Request DTOs ──

#[derive(Debug, Deserialize)]
pub struct AppleAuthRequest {
    pub identity_token: String,
    pub authorization_code: Option<String>,
    pub full_name: Option<String>,
    pub email: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GoogleAuthRequest {
    pub authorization_code: String,
    #[serde(default = "default_google_redirect")]
    pub redirect_uri: String,
}

fn default_google_redirect() -> String {
    "urn:ietf:wg:oauth:2.0:oob".into()
}

#[derive(Debug, Deserialize)]
pub struct ChatGPTAuthRequest {
    pub authorization_code: String,
    pub redirect_uri: String,
    pub code_verifier: String,
}

#[derive(Debug, Deserialize)]
pub struct RefreshTokenRequest {
    pub refresh_token: String,
}

// ── Response DTOs ──

#[derive(Debug, Serialize)]
pub struct AuthUserInfo {
    pub id: String,
    pub email: Option<String>,
    pub display_name: Option<String>,
    pub subscription_tier: String,
    pub is_pro: bool,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub user: AuthUserInfo,
}

// ── Helpers ──

async fn get_or_create_user(
    pool: &SqlitePool,
    provider_column: &str,
    provider_sub: &str,
    email: Option<&str>,
) -> Result<crate::models::User, AppError> {
    // Look up by provider ID
    let query = format!("SELECT * FROM users WHERE {} = ?", provider_column);
    let user = sqlx::query_as::<_, crate::models::User>(&query)
        .bind(provider_sub)
        .fetch_optional(pool)
        .await?;

    if let Some(user) = user {
        return Ok(user);
    }

    // Try to find by email and link provider
    if let Some(email) = email {
        let user = sqlx::query_as::<_, crate::models::User>(
            "SELECT * FROM users WHERE email = ?",
        )
        .bind(email)
        .fetch_optional(pool)
        .await?;

        if let Some(user) = user {
            let update_query = format!("UPDATE users SET {} = ? WHERE id = ?", provider_column);
            sqlx::query(&update_query)
                .bind(provider_sub)
                .bind(user.id)
                .execute(pool)
                .await?;
            // Re-fetch with updated field
            let user = sqlx::query_as::<_, crate::models::User>(
                "SELECT * FROM users WHERE id = ?",
            )
            .bind(user.id)
            .fetch_one(pool)
            .await?;
            return Ok(user);
        }
    }

    // Create new user
    let insert_query = format!(
        "INSERT INTO users ({}, email) VALUES (?, ?)",
        provider_column
    );
    let result = sqlx::query(&insert_query)
        .bind(provider_sub)
        .bind(email)
        .execute(pool)
        .await?;

    let user_id = result.last_insert_rowid();

    // Create free subscription
    sqlx::query("INSERT INTO subscriptions (user_id, tier) VALUES (?, 'free')")
        .bind(user_id)
        .execute(pool)
        .await?;

    let user = sqlx::query_as::<_, crate::models::User>(
        "SELECT * FROM users WHERE id = ?",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(user)
}

async fn build_user_info(
    pool: &SqlitePool,
    user: &crate::models::User,
) -> Result<AuthUserInfo, AppError> {
    let sub = sqlx::query_as::<_, crate::models::Subscription>(
        "SELECT * FROM subscriptions WHERE user_id = ?",
    )
    .bind(user.id)
    .fetch_optional(pool)
    .await?;

    let tier_raw = sub
        .as_ref()
        .map(|s| s.tier.as_str())
        .unwrap_or("free");
    let tier = tier_raw.to_lowercase();

    let is_pro = if let Some(ref s) = sub {
        s.tier.eq_ignore_ascii_case("pro")
            && s.expires_at
                .as_ref()
                .map(|exp| exp > &chrono::Utc::now().to_rfc3339())
                .unwrap_or(true)
    } else {
        false
    };

    let display_name = user
        .email
        .as_ref()
        .and_then(|e| e.split('@').next())
        .map(String::from);

    Ok(AuthUserInfo {
        id: user.id.to_string(),
        email: user.email.clone(),
        display_name,
        subscription_tier: tier,
        is_pro,
    })
}

async fn build_auth_response(
    pool: &SqlitePool,
    user: &crate::models::User,
    config: &Config,
) -> Result<AuthResponse, AppError> {
    let user_info = build_user_info(pool, user).await?;

    let access_token = create_access_token(user.id, config)
        .map_err(|e| AppError::Internal(e))?;
    let refresh_token = create_refresh_token(user.id, config)
        .map_err(|e| AppError::Internal(e))?;

    Ok(AuthResponse {
        access_token,
        refresh_token,
        token_type: "bearer".into(),
        user: user_info,
    })
}

// ── Route Handlers ──

pub async fn apple_sign_in(
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Json(body): Json<AppleAuthRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let token_data = verify_apple_identity_token(&body.identity_token, &config)
        .await
        .map_err(|e| AppError::Unauthorized(e))?;

    let email = body.email.as_deref().or(token_data.email.as_deref());
    let user = get_or_create_user(&pool, "apple_user_id", &token_data.sub, email).await?;
    let resp = build_auth_response(&pool, &user, &config).await?;
    Ok(Json(resp))
}

pub async fn google_sign_in(
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Json(body): Json<GoogleAuthRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let user_info = exchange_google_auth_code(&body.authorization_code, &body.redirect_uri, &config)
        .await
        .map_err(|e| AppError::Unauthorized(e))?;

    let user =
        get_or_create_user(&pool, "google_user_id", &user_info.sub, user_info.email.as_deref())
            .await?;

    if let Some(ref rt) = user_info.refresh_token {
        sqlx::query("UPDATE users SET google_refresh_token = ? WHERE id = ?")
            .bind(rt)
            .bind(user.id)
            .execute(&pool)
            .await?;
    }

    let resp = build_auth_response(&pool, &user, &config).await?;
    Ok(Json(resp))
}

pub async fn chatgpt_connect(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
    Json(body): Json<ChatGPTAuthRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user_info = exchange_chatgpt_auth_code(
        &body.authorization_code,
        &body.redirect_uri,
        &body.code_verifier,
    )
    .await
    .map_err(|e| AppError::Unauthorized(e))?;

    if current_user.openai_user_id.is_none() {
        sqlx::query(
            "UPDATE users SET openai_access_token = ?, openai_refresh_token = ?, openai_user_id = ? WHERE id = ?",
        )
        .bind(&user_info.access_token)
        .bind(&user_info.refresh_token)
        .bind(&user_info.sub)
        .bind(current_user.id)
        .execute(&pool)
        .await?;
    } else {
        sqlx::query(
            "UPDATE users SET openai_access_token = ?, openai_refresh_token = ? WHERE id = ?",
        )
        .bind(&user_info.access_token)
        .bind(&user_info.refresh_token)
        .bind(current_user.id)
        .execute(&pool)
        .await?;
    }

    Ok(Json(serde_json::json!({
        "status": "connected",
        "email": user_info.email
    })))
}

pub async fn google_connect(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Json(body): Json<GoogleAuthRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user_info = exchange_google_auth_code(&body.authorization_code, &body.redirect_uri, &config)
        .await
        .map_err(|e| AppError::Unauthorized(e))?;

    if let Some(ref rt) = user_info.refresh_token {
        sqlx::query("UPDATE users SET google_refresh_token = ? WHERE id = ?")
            .bind(rt)
            .bind(current_user.id)
            .execute(&pool)
            .await?;
    }
    if current_user.google_user_id.is_none() {
        if let Some(ref sub) = Some(&user_info.sub) {
            sqlx::query("UPDATE users SET google_user_id = ? WHERE id = ?")
                .bind(sub)
                .bind(current_user.id)
                .execute(&pool)
                .await?;
        }
    }
    if current_user.email.is_none() {
        if let Some(ref email) = user_info.email {
            sqlx::query("UPDATE users SET email = ? WHERE id = ?")
                .bind(email)
                .bind(current_user.id)
                .execute(&pool)
                .await?;
        }
    }

    Ok(Json(serde_json::json!({
        "status": "connected",
        "email": user_info.email
    })))
}

pub async fn refresh_token(
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Json(body): Json<RefreshTokenRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let claims = verify_token(&body.refresh_token, TOKEN_TYPE_REFRESH, &config)
        .map_err(|e| AppError::Unauthorized(e))?;

    let user_id: i64 = claims
        .sub
        .parse()
        .map_err(|_| AppError::Unauthorized("Invalid user ID".into()))?;

    let user = sqlx::query_as::<_, crate::models::User>("SELECT * FROM users WHERE id = ?")
        .bind(user_id)
        .fetch_optional(&pool)
        .await?
        .ok_or_else(|| AppError::Unauthorized("User not found".into()))?;

    let resp = build_auth_response(&pool, &user, &config).await?;
    Ok(Json(resp))
}

pub async fn dev_login(
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
) -> Result<Json<AuthResponse>, AppError> {
    let email = "dev@test.com";
    let user = sqlx::query_as::<_, crate::models::User>("SELECT * FROM users WHERE email = ?")
        .bind(email)
        .fetch_optional(&pool)
        .await?;

    let user = if let Some(user) = user {
        user
    } else {
        sqlx::query("INSERT INTO users (email) VALUES (?)")
            .bind(email)
            .execute(&pool)
            .await?;

        let user = sqlx::query_as::<_, crate::models::User>("SELECT * FROM users WHERE email = ?")
            .bind(email)
            .fetch_one(&pool)
            .await?;

        sqlx::query("INSERT INTO subscriptions (user_id, tier) VALUES (?, 'free')")
            .bind(user.id)
            .execute(&pool)
            .await?;

        user
    };

    let resp = build_auth_response(&pool, &user, &config).await?;
    Ok(Json(resp))
}

pub async fn get_me(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
) -> Result<Json<AuthUserInfo>, AppError> {
    let info = build_user_info(&pool, &current_user).await?;
    Ok(Json(info))
}

const GOOGLE_OAUTH_SCOPES: &str =
    "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile";

pub async fn google_login_redirect(
    Extension(config): Extension<Config>,
) -> impl IntoResponse {
    let callback_uri = "http://127.0.0.1:8000/auth/google/callback";
    let params = url_encode_params(&[
        ("client_id", &config.google_client_id),
        ("redirect_uri", &callback_uri.to_string()),
        ("response_type", &"code".to_string()),
        ("scope", &GOOGLE_OAUTH_SCOPES.to_string()),
        ("access_type", &"offline".to_string()),
        ("prompt", &"consent".to_string()),
    ]);
    Redirect::temporary(&format!(
        "https://accounts.google.com/o/oauth2/v2/auth?{params}"
    ))
}

fn url_encode_params(params: &[(&str, &String)]) -> String {
    params
        .iter()
        .map(|(k, v)| {
            format!(
                "{}={}",
                urlencoding(k),
                urlencoding(v)
            )
        })
        .collect::<Vec<_>>()
        .join("&")
}

fn urlencoding(s: &str) -> String {
    let mut result = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                result.push(b as char);
            }
            _ => {
                result.push_str(&format!("%{:02X}", b));
            }
        }
    }
    result
}

#[derive(Debug, Deserialize)]
pub struct GoogleCallbackQuery {
    pub code: String,
}

pub async fn google_callback(
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Query(query): Query<GoogleCallbackQuery>,
) -> Result<Json<AuthResponse>, AppError> {
    let callback_uri = "http://127.0.0.1:8000/auth/google/callback";
    let user_info = exchange_google_auth_code(&query.code, callback_uri, &config)
        .await
        .map_err(|e| AppError::Unauthorized(e))?;

    let user = get_or_create_user(
        &pool,
        "google_user_id",
        &user_info.sub,
        user_info.email.as_deref(),
    )
    .await?;

    if let Some(ref rt) = user_info.refresh_token {
        sqlx::query("UPDATE users SET google_refresh_token = ? WHERE id = ?")
            .bind(rt)
            .bind(user.id)
            .execute(&pool)
            .await?;
    }

    let resp = build_auth_response(&pool, &user, &config).await?;
    Ok(Json(resp))
}
