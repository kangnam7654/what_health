use axum::extract::{Extension, Query};
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::SqlitePool;

use crate::auth::middleware::AuthUser;
use crate::config::Config;
use crate::error::AppError;
use crate::llm::gemini::list_gemini_models;
use crate::llm::proxy::{list_openai_models, proxy_llm_request};
use crate::quota::service::decrement_quota;

#[derive(Debug, Deserialize)]
pub struct LLMProxyRequest {
    pub messages: Vec<Message>,
    #[serde(default = "default_provider")]
    pub provider: String,
    pub model: Option<String>,
    #[serde(default = "default_max_tokens")]
    pub max_tokens: i32,
    #[serde(default = "default_temperature")]
    pub temperature: f64,
}

fn default_provider() -> String {
    "openai".into()
}
fn default_max_tokens() -> i32 {
    2048
}
fn default_temperature() -> f64 {
    0.7
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Serialize)]
pub struct LLMProxyResponse {
    pub content: String,
    pub provider: String,
    pub model: String,
    pub usage: Option<Value>,
}

async fn handle_llm_request(
    body: LLMProxyRequest,
    current_user: &crate::models::User,
    pool: &SqlitePool,
    config: &Config,
) -> Result<Json<LLMProxyResponse>, AppError> {
    let allowed = decrement_quota(pool, current_user.id).await?;
    if !allowed {
        return Err(AppError::TooManyRequests(
            "Watch a reward ad for extra requests.".into(),
        ));
    }

    let messages: Vec<Value> = body
        .messages
        .iter()
        .map(|m| json!({"role": &m.role, "content": &m.content}))
        .collect();

    let result = proxy_llm_request(
        &messages,
        &body.provider,
        body.model.as_deref(),
        body.max_tokens,
        body.temperature,
        current_user.google_refresh_token.as_deref(),
        current_user.openai_access_token.as_deref(),
        current_user.openai_refresh_token.as_deref(),
        config,
    )
    .await
    .map_err(|e| {
        tracing::error!("LLM proxy error for user {}: {e}", current_user.id);
        AppError::BadGateway(e)
    })?;

    Ok(Json(LLMProxyResponse {
        content: result.content,
        provider: result.provider,
        model: result.model,
        usage: Some(result.usage),
    }))
}

pub async fn chat(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Json(body): Json<LLMProxyRequest>,
) -> Result<Json<LLMProxyResponse>, AppError> {
    handle_llm_request(body, &current_user, &pool, &config).await
}

#[derive(Debug, Deserialize)]
pub struct ModelsQuery {
    #[serde(default = "default_models_provider")]
    pub provider: String,
}

fn default_models_provider() -> String {
    "codex".into()
}

pub async fn get_models(
    AuthUser(current_user): AuthUser,
    Extension(config): Extension<Config>,
    Query(query): Query<ModelsQuery>,
) -> Result<Json<Value>, AppError> {
    match query.provider.as_str() {
        "codex" | "openai" => {
            let models = list_openai_models(
                current_user.openai_access_token.as_deref(),
                current_user.openai_refresh_token.as_deref(),
                &config,
            )
            .await;
            let has_oauth = current_user.openai_access_token.is_some()
                || current_user.openai_refresh_token.is_some();
            Ok(Json(json!({"models": models, "has_oauth": has_oauth})))
        }
        "gemini" => {
            let models =
                list_gemini_models(current_user.google_refresh_token.as_deref(), &config).await;
            let has_oauth = current_user.google_refresh_token.is_some();
            Ok(Json(json!({"models": models, "has_oauth": has_oauth})))
        }
        _ => Ok(Json(json!({"models": [], "has_oauth": false}))),
    }
}

pub async fn generate_plan(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
    Extension(config): Extension<Config>,
    Json(body): Json<LLMProxyRequest>,
) -> Result<Json<LLMProxyResponse>, AppError> {
    handle_llm_request(body, &current_user, &pool, &config).await
}
