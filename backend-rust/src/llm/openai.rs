use serde_json::{json, Value};

use crate::config::Config;

const OPENAI_CHAT_URL: &str = "https://api.openai.com/v1/chat/completions";
pub const OPENAI_DEFAULT_MODEL: &str = "gpt-4o-mini";

pub struct LlmResponse {
    pub content: String,
    pub provider: String,
    pub model: String,
    pub usage: Value,
}

pub async fn call_openai(
    messages: &[Value],
    model: Option<&str>,
    max_tokens: i32,
    temperature: f64,
    config: &Config,
) -> Result<LlmResponse, String> {
    if config.openai_api_key.is_empty() {
        return Err("OpenAI API key not configured".into());
    }

    let model = model.unwrap_or(OPENAI_DEFAULT_MODEL);
    let payload = json!({
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    });

    let client = reqwest::Client::new();
    let resp = client
        .post(OPENAI_CHAT_URL)
        .bearer_auth(&config.openai_api_key)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(60))
        .send()
        .await
        .map_err(|e| format!("OpenAI API error: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        tracing::error!("OpenAI API error {status}: {text}");
        return Err(format!("OpenAI API error: {status}"));
    }

    let data: Value = resp.json().await.map_err(|e| format!("Failed to parse OpenAI response: {e}"))?;

    let content = data["choices"][0]["message"]["content"]
        .as_str()
        .unwrap_or("")
        .to_string();

    let usage = data.get("usage").cloned().unwrap_or(json!({}));

    Ok(LlmResponse {
        content,
        provider: "openai".into(),
        model: model.to_string(),
        usage: json!({
            "prompt_tokens": usage.get("prompt_tokens").and_then(|v| v.as_i64()).unwrap_or(0),
            "completion_tokens": usage.get("completion_tokens").and_then(|v| v.as_i64()).unwrap_or(0),
            "total_tokens": usage.get("total_tokens").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
    })
}
