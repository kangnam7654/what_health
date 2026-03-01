use serde_json::{json, Value};

use crate::config::Config;
use crate::llm::codex::call_codex;
use crate::llm::gemini::call_gemini;
use crate::llm::openai::{call_openai, LlmResponse};

// Known ChatGPT OAuth models
fn chatgpt_oauth_models() -> Vec<Value> {
    vec![
        json!({"id": "gpt-5.3-codex", "owned_by": "openai"}),
        json!({"id": "gpt-5.2-codex", "owned_by": "openai"}),
        json!({"id": "gpt-5.2", "owned_by": "openai"}),
        json!({"id": "gpt-5", "owned_by": "openai"}),
        json!({"id": "gpt-5-mini", "owned_by": "openai"}),
        json!({"id": "gpt-5-nano", "owned_by": "openai"}),
        json!({"id": "o3", "owned_by": "openai"}),
        json!({"id": "o3-pro", "owned_by": "openai"}),
        json!({"id": "o3-mini", "owned_by": "openai"}),
    ]
}

pub async fn proxy_llm_request(
    messages: &[Value],
    provider: &str,
    model: Option<&str>,
    max_tokens: i32,
    temperature: f64,
    google_refresh_token: Option<&str>,
    openai_access_token: Option<&str>,
    openai_refresh_token: Option<&str>,
    config: &Config,
) -> Result<LlmResponse, String> {
    match provider {
        "gemini" => {
            call_gemini(
                messages,
                model,
                max_tokens,
                temperature,
                google_refresh_token,
                config,
            )
            .await
        }
        "codex" => {
            call_codex(
                messages,
                model,
                openai_access_token,
                openai_refresh_token,
                config,
            )
            .await
        }
        _ => call_openai(messages, model, max_tokens, temperature, config).await,
    }
}

pub async fn list_openai_models(
    openai_access_token: Option<&str>,
    openai_refresh_token: Option<&str>,
    config: &Config,
) -> Vec<Value> {
    let mut auth_header: Option<String> = None;

    if let Some(token) = openai_access_token {
        auth_header = Some(format!("Bearer {token}"));
    } else if let Some(refresh_token) = openai_refresh_token {
        if let Ok(token) = super::codex::refresh_openai_token(refresh_token).await {
            auth_header = Some(token);
        }
    } else if !config.openai_api_key.is_empty() {
        auth_header = Some(format!("Bearer {}", config.openai_api_key));
    }

    if let Some(auth) = auth_header {
        let client = reqwest::Client::new();
        if let Ok(resp) = client
            .get("https://api.openai.com/v1/models")
            .header("Authorization", &auth)
            .timeout(std::time::Duration::from_secs(10))
            .send()
            .await
        {
            if resp.status().is_success() {
                if let Ok(data) = resp.json::<Value>().await {
                    let mut models: Vec<Value> = data
                        .get("data")
                        .and_then(|v| v.as_array())
                        .map(|arr| {
                            arr.iter()
                                .map(|m| {
                                    json!({
                                        "id": m.get("id").and_then(|v| v.as_str()).unwrap_or(""),
                                        "owned_by": m.get("owned_by").and_then(|v| v.as_str()).unwrap_or(""),
                                    })
                                })
                                .collect()
                        })
                        .unwrap_or_default();

                    if !models.is_empty() {
                        models.sort_by(|a, b| {
                            let a_id = a.get("id").and_then(|v| v.as_str()).unwrap_or("");
                            let b_id = b.get("id").and_then(|v| v.as_str()).unwrap_or("");
                            a_id.cmp(b_id)
                        });
                        return models;
                    }
                }
            }
        }
    }

    chatgpt_oauth_models()
}
