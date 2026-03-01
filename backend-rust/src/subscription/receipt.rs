use chrono::DateTime;
use serde_json::Value;

use crate::models::SubscriptionTier;

const APP_STORE_SANDBOX_URL: &str = "https://sandbox.itunes.apple.com/verifyReceipt";
const APP_STORE_PRODUCTION_URL: &str = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_RECEIPT_IS_SANDBOX: i64 = 21007;

fn product_id_to_tier(product_id: &str) -> SubscriptionTier {
    if product_id.starts_with("com.whathealth.app.pro.monthly") {
        SubscriptionTier::Pro
    } else {
        SubscriptionTier::Free
    }
}

async fn verify_with_apple(receipt_data: &str, url: &str) -> Result<Value, String> {
    let client = reqwest::Client::new();
    let payload = serde_json::json!({
        "receipt-data": receipt_data,
        "password": "",
        "exclude-old-transactions": true,
    });

    let resp = client
        .post(url)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| format!("Failed to contact Apple servers: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!(
            "Apple server returned status: {}",
            resp.status()
        ));
    }

    resp.json::<Value>()
        .await
        .map_err(|e| format!("Failed to parse Apple response: {e}"))
}

pub struct ReceiptValidationResult {
    pub tier: SubscriptionTier,
    pub expires_at: Option<String>,
    pub transaction_id: Option<String>,
    pub product_id: String,
}

pub async fn validate_apple_receipt(
    receipt_data: &str,
    product_id: &str,
    transaction_id: Option<&str>,
) -> Result<ReceiptValidationResult, String> {
    let mut result = verify_with_apple(receipt_data, APP_STORE_PRODUCTION_URL).await?;
    let mut status = result
        .get("status")
        .and_then(|v| v.as_i64())
        .unwrap_or(-1);

    if status == APPLE_RECEIPT_IS_SANDBOX {
        tracing::info!("Production receipt is from sandbox, retrying with sandbox URL");
        result = verify_with_apple(receipt_data, APP_STORE_SANDBOX_URL).await?;
        status = result
            .get("status")
            .and_then(|v| v.as_i64())
            .unwrap_or(-1);
    }

    if status != 0 {
        return Err(format!(
            "Apple receipt validation failed with status: {status}"
        ));
    }

    let mut latest_receipts = result
        .get("latest_receipt_info")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    if latest_receipts.is_empty() {
        latest_receipts = result
            .get("receipt")
            .and_then(|v| v.get("in_app"))
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        if latest_receipts.is_empty() {
            return Err("No receipt info found in Apple response".into());
        }
    }

    // Find matching receipt or use last
    let matching: Vec<&Value> = latest_receipts
        .iter()
        .filter(|r| {
            r.get("product_id")
                .and_then(|v| v.as_str())
                .map(|p| p == product_id)
                .unwrap_or(false)
        })
        .collect();

    let receipt_info = if let Some(last) = matching.last() {
        (*last).clone()
    } else {
        latest_receipts.last().cloned().unwrap()
    };

    let expires_at = receipt_info
        .get("expires_date_ms")
        .and_then(|v| v.as_str())
        .and_then(|ms_str| ms_str.parse::<i64>().ok())
        .and_then(|ms| {
            DateTime::from_timestamp(ms / 1000, ((ms % 1000) * 1_000_000) as u32)
        })
        .map(|dt| dt.to_rfc3339());

    let found_transaction_id = receipt_info
        .get("transaction_id")
        .and_then(|v| v.as_str())
        .map(String::from)
        .or_else(|| transaction_id.map(String::from));

    let found_product_id = receipt_info
        .get("product_id")
        .and_then(|v| v.as_str())
        .unwrap_or(product_id)
        .to_string();

    let tier = product_id_to_tier(&found_product_id);

    Ok(ReceiptValidationResult {
        tier,
        expires_at,
        transaction_id: found_transaction_id,
        product_id: found_product_id,
    })
}
