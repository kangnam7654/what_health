use axum::extract::Extension;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::subscription::receipt::validate_apple_receipt;

#[derive(Debug, Deserialize)]
pub struct VerifyReceiptRequest {
    pub receipt_data: String,
    pub product_id: String,
    pub transaction_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct VerifyReceiptResponse {
    pub success: bool,
    pub new_tier: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SubscriptionResponse {
    pub tier: String,
    pub expires_at: Option<String>,
    pub product_id: Option<String>,
}

pub async fn verify_receipt(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
    Json(body): Json<VerifyReceiptRequest>,
) -> Result<Json<VerifyReceiptResponse>, AppError> {
    let validation_result = validate_apple_receipt(
        &body.receipt_data,
        &body.product_id,
        body.transaction_id.as_deref(),
    )
    .await
    .map_err(|e| {
        tracing::error!(
            "Receipt validation error for user {}: {}",
            current_user.id,
            e
        );
        AppError::BadRequest(e)
    })?;

    let tier_str = validation_result.tier.as_str();

    // Check if subscription exists
    let existing = sqlx::query_scalar::<_, i64>(
        "SELECT id FROM subscriptions WHERE user_id = ?",
    )
    .bind(current_user.id)
    .fetch_optional(&pool)
    .await?;

    if let Some(sub_id) = existing {
        sqlx::query(
            "UPDATE subscriptions SET tier = ?, expires_at = ?, transaction_id = ?, product_id = ? WHERE id = ?",
        )
        .bind(tier_str)
        .bind(&validation_result.expires_at)
        .bind(&validation_result.transaction_id)
        .bind(&validation_result.product_id)
        .bind(sub_id)
        .execute(&pool)
        .await?;
    } else {
        sqlx::query(
            "INSERT INTO subscriptions (user_id, tier, expires_at, transaction_id, product_id) VALUES (?, ?, ?, ?, ?)",
        )
        .bind(current_user.id)
        .bind(tier_str)
        .bind(&validation_result.expires_at)
        .bind(&validation_result.transaction_id)
        .bind(&validation_result.product_id)
        .execute(&pool)
        .await?;
    }

    Ok(Json(VerifyReceiptResponse {
        success: true,
        new_tier: Some(tier_str.to_string()),
        expires_at: validation_result.expires_at,
    }))
}

pub async fn get_subscription(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
) -> Result<Json<SubscriptionResponse>, AppError> {
    let sub = sqlx::query_as::<_, crate::models::Subscription>(
        "SELECT * FROM subscriptions WHERE user_id = ?",
    )
    .bind(current_user.id)
    .fetch_optional(&pool)
    .await?;

    match sub {
        Some(s) => Ok(Json(SubscriptionResponse {
            tier: s.tier.to_lowercase(),
            expires_at: s.expires_at,
            product_id: s.product_id,
        })),
        None => Ok(Json(SubscriptionResponse {
            tier: "free".into(),
            expires_at: None,
            product_id: None,
        })),
    }
}
