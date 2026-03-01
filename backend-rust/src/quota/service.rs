use chrono::Utc;
use sqlx::SqlitePool;

use crate::error::AppError;
use crate::models::UsageRecord;

pub const DAILY_LIMIT: i32 = 200;
pub const BONUS_PER_AD: i32 = 10;
pub const MAX_REWARD_ADS_PER_DAY: i32 = 5;

async fn get_or_create_usage(
    pool: &SqlitePool,
    user_id: i64,
    today: &str,
) -> Result<UsageRecord, AppError> {
    let record = sqlx::query_as::<_, UsageRecord>(
        "SELECT * FROM usage_records WHERE user_id = ? AND date = ?",
    )
    .bind(user_id)
    .bind(today)
    .fetch_optional(pool)
    .await?;

    if let Some(record) = record {
        return Ok(record);
    }

    sqlx::query(
        "INSERT INTO usage_records (user_id, date, request_count, bonus_count, reward_ads_watched) VALUES (?, ?, 0, 0, 0)",
    )
    .bind(user_id)
    .bind(today)
    .execute(pool)
    .await?;

    let record = sqlx::query_as::<_, UsageRecord>(
        "SELECT * FROM usage_records WHERE user_id = ? AND date = ?",
    )
    .bind(user_id)
    .bind(today)
    .fetch_one(pool)
    .await?;

    Ok(record)
}

pub async fn decrement_quota(pool: &SqlitePool, user_id: i64) -> Result<bool, AppError> {
    let today = Utc::now().format("%Y-%m-%d").to_string();
    let record = get_or_create_usage(pool, user_id, &today).await?;

    let bonus_available = record.reward_ads_watched * BONUS_PER_AD;

    if record.request_count < DAILY_LIMIT {
        sqlx::query("UPDATE usage_records SET request_count = request_count + 1 WHERE id = ?")
            .bind(record.id)
            .execute(pool)
            .await?;
        return Ok(true);
    }

    if record.bonus_count < bonus_available {
        sqlx::query("UPDATE usage_records SET bonus_count = bonus_count + 1 WHERE id = ?")
            .bind(record.id)
            .execute(pool)
            .await?;
        return Ok(true);
    }

    Ok(false)
}

pub struct QuotaInfo {
    pub daily_limit: i32,
    pub requests_today: i32,
    pub remaining: i32,
    pub bonus_remaining: i32,
    pub reward_ads_watched: i32,
    pub max_reward_ads: i32,
    pub resets_at: String,
}

pub async fn get_quota_info(pool: &SqlitePool, user_id: i64) -> Result<QuotaInfo, AppError> {
    let today = Utc::now().format("%Y-%m-%d").to_string();
    let record = get_or_create_usage(pool, user_id, &today).await?;

    let bonus_available = record.reward_ads_watched * BONUS_PER_AD;
    let bonus_remaining = (bonus_available - record.bonus_count).max(0);

    let today_date = Utc::now().date_naive();
    let tomorrow = today_date
        .succ_opt()
        .unwrap_or(today_date);
    let resets_at = format!("{}T00:00:00+00:00", tomorrow);

    Ok(QuotaInfo {
        daily_limit: DAILY_LIMIT,
        requests_today: record.request_count,
        remaining: (DAILY_LIMIT - record.request_count).max(0),
        bonus_remaining,
        reward_ads_watched: record.reward_ads_watched,
        max_reward_ads: MAX_REWARD_ADS_PER_DAY,
        resets_at,
    })
}

pub struct RewardResult {
    pub success: bool,
    pub bonus_available: i32,
    pub ads_remaining: i32,
}

pub async fn grant_reward_bonus(pool: &SqlitePool, user_id: i64) -> Result<RewardResult, AppError> {
    let today = Utc::now().format("%Y-%m-%d").to_string();
    let record = get_or_create_usage(pool, user_id, &today).await?;

    if record.reward_ads_watched >= MAX_REWARD_ADS_PER_DAY {
        let bonus_available =
            (record.reward_ads_watched * BONUS_PER_AD - record.bonus_count).max(0);
        return Ok(RewardResult {
            success: false,
            bonus_available,
            ads_remaining: 0,
        });
    }

    sqlx::query(
        "UPDATE usage_records SET reward_ads_watched = reward_ads_watched + 1 WHERE id = ?",
    )
    .bind(record.id)
    .execute(pool)
    .await?;

    let new_watched = record.reward_ads_watched + 1;
    let bonus_available = (new_watched * BONUS_PER_AD - record.bonus_count).max(0);
    let ads_remaining = MAX_REWARD_ADS_PER_DAY - new_watched;

    Ok(RewardResult {
        success: true,
        bonus_available,
        ads_remaining,
    })
}
