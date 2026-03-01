use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct User {
    pub id: i64,
    pub apple_user_id: Option<String>,
    pub google_user_id: Option<String>,
    pub openai_user_id: Option<String>,
    pub email: Option<String>,
    pub google_refresh_token: Option<String>,
    pub openai_access_token: Option<String>,
    pub openai_refresh_token: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SubscriptionTier {
    Free,
    Pro,
}

impl SubscriptionTier {
    pub fn as_str(&self) -> &str {
        match self {
            SubscriptionTier::Free => "free",
            SubscriptionTier::Pro => "pro",
        }
    }

    pub fn from_str_val(s: &str) -> Self {
        match s {
            "pro" => SubscriptionTier::Pro,
            _ => SubscriptionTier::Free,
        }
    }
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Subscription {
    pub id: i64,
    pub user_id: i64,
    pub tier: String,
    pub expires_at: Option<String>,
    pub product_id: Option<String>,
    pub transaction_id: Option<String>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UsageRecord {
    pub id: i64,
    pub user_id: i64,
    pub date: String,
    pub request_count: i32,
    pub bonus_count: i32,
    pub reward_ads_watched: i32,
}
