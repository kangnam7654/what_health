use axum::extract::Extension;
use axum::Json;
use serde::Serialize;
use sqlx::SqlitePool;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;
use crate::quota::service::{get_quota_info, grant_reward_bonus, BONUS_PER_AD};

#[derive(Debug, Serialize)]
pub struct QuotaResponse {
    pub requests_today: i32,
    pub daily_limit: i32,
    pub remaining: i32,
    pub bonus_remaining: i32,
    pub reward_ads_watched: i32,
    pub max_reward_ads: i32,
    pub resets_at: String,
}

#[derive(Debug, Serialize)]
pub struct RewardClaimResponse {
    pub success: bool,
    pub bonus_granted: i32,
    pub bonus_available: i32,
    pub reward_ads_remaining: i32,
}

pub async fn get_quota(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
) -> Result<Json<QuotaResponse>, AppError> {
    let info = get_quota_info(&pool, current_user.id).await?;
    Ok(Json(QuotaResponse {
        requests_today: info.requests_today,
        daily_limit: info.daily_limit,
        remaining: info.remaining,
        bonus_remaining: info.bonus_remaining,
        reward_ads_watched: info.reward_ads_watched,
        max_reward_ads: info.max_reward_ads,
        resets_at: info.resets_at,
    }))
}

pub async fn claim_reward_ad(
    AuthUser(current_user): AuthUser,
    Extension(pool): Extension<SqlitePool>,
) -> Result<Json<RewardClaimResponse>, AppError> {
    let result = grant_reward_bonus(&pool, current_user.id).await?;
    Ok(Json(RewardClaimResponse {
        success: result.success,
        bonus_granted: if result.success { BONUS_PER_AD } else { 0 },
        bonus_available: result.bonus_available,
        reward_ads_remaining: result.ads_remaining,
    }))
}
