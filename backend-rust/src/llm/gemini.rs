use serde_json::{json, Value};

use crate::config::Config;

const CLOUDCODE_BASE_URL: &str = "https://cloudcode-pa.googleapis.com";
const CLOUDCODE_API_VERSION: &str = "v1internal";
const GEMINI_BASE_URL: &str = "https://generativelanguage.googleapis.com/v1beta/models";
pub const GEMINI_DEFAULT_MODEL: &str = "gemini-3-flash-preview";
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";

fn user_agent() -> String {
    format!(
        "GeminiCLI/0.1.5 ({}_{})",
        std::env::consts::OS.to_uppercase(),
        std::env::consts::ARCH.to_uppercase()
    )
}

pub fn messages_to_gemini_contents(messages: &[Value]) -> (Vec<Value>, Vec<Value>) {
    let mut contents = Vec::new();
    let mut system_parts = Vec::new();

    for msg in messages {
        let role = msg.get("role").and_then(|v| v.as_str()).unwrap_or("");
        let content = msg.get("content").and_then(|v| v.as_str()).unwrap_or("");

        if role == "system" {
            system_parts.push(json!({"text": content}));
            continue;
        }

        let gemini_role = if role == "user" { "user" } else { "model" };
        contents.push(json!({
            "role": gemini_role,
            "parts": [{"text": content}],
        }));
    }

    (contents, system_parts)
}

pub async fn refresh_google_access_token(
    refresh_token: &str,
    config: &Config,
) -> Result<String, String> {
    let client = reqwest::Client::new();
    let params = [
        ("client_id", config.google_client_id.as_str()),
        ("client_secret", config.google_client_secret.as_str()),
        ("refresh_token", refresh_token),
        ("grant_type", "refresh_token"),
    ];

    let resp = client
        .post(GOOGLE_TOKEN_URL)
        .form(&params)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("Google token refresh failed: {e}"))?;

    if !resp.status().is_success() {
        let text = resp.text().await.unwrap_or_default();
        tracing::error!("Google token refresh failed: {text}");
        return Err(format!("Google token refresh failed"));
    }

    let data: Value = resp.json().await.map_err(|e| format!("Failed to parse token response: {e}"))?;
    data.get("access_token")
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| "No access_token in Google token response".into())
}

async fn cloudcode_load_project(access_token: &str) -> Result<String, String> {
    let url = format!("{CLOUDCODE_BASE_URL}/{CLOUDCODE_API_VERSION}:loadCodeAssist");
    let ua = user_agent();

    let payload = json!({
        "metadata": {
            "ideType": "IDE_UNSPECIFIED",
            "platform": format!("{}_{}", std::env::consts::OS.to_uppercase(), std::env::consts::ARCH.to_uppercase()),
            "pluginType": "GEMINI",
            "duetProject": null,
        }
    });

    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .bearer_auth(access_token)
        .header("User-Agent", &ua)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("loadCodeAssist failed: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        tracing::error!("loadCodeAssist failed {status}: {text}");
        return Err(format!("loadCodeAssist failed: {status}"));
    }

    let data: Value = resp.json().await.map_err(|e| format!("Failed to parse loadCodeAssist response: {e}"))?;
    data.get("cloudaicompanionProject")
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| "No cloudaicompanionProject in loadCodeAssist response".into())
}

async fn call_gemini_via_cloudcode(
    access_token: &str,
    model: &str,
    contents: &[Value],
    system_parts: &[Value],
    max_tokens: i32,
    temperature: f64,
) -> Result<Value, String> {
    let project = cloudcode_load_project(access_token).await?;
    let ua = user_agent();

    let mut inner_request = json!({
        "contents": contents,
        "generationConfig": {
            "maxOutputTokens": max_tokens,
            "temperature": temperature,
        },
    });

    if !system_parts.is_empty() {
        inner_request.as_object_mut().unwrap().insert(
            "systemInstruction".into(),
            json!({
                "role": "user",
                "parts": system_parts,
            }),
        );
    }

    let payload = json!({
        "model": model,
        "project": project,
        "request": inner_request,
    });

    let url = format!("{CLOUDCODE_BASE_URL}/{CLOUDCODE_API_VERSION}:generateContent");
    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .bearer_auth(access_token)
        .header("User-Agent", &ua)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(60))
        .send()
        .await
        .map_err(|e| format!("Gemini API error: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        tracing::error!("CloudCode generateContent {status}: {text}");
        return Err(format!("Gemini API error: {status}"));
    }

    let data: Value = resp.json().await.map_err(|e| format!("Failed to parse Gemini response: {e}"))?;
    Ok(data.get("response").cloned().unwrap_or(data))
}

pub use super::openai::LlmResponse;

pub async fn call_gemini(
    messages: &[Value],
    model: Option<&str>,
    max_tokens: i32,
    temperature: f64,
    google_refresh_token: Option<&str>,
    config: &Config,
) -> Result<LlmResponse, String> {
    let model = model.unwrap_or(GEMINI_DEFAULT_MODEL);
    let (contents, system_parts) = messages_to_gemini_contents(messages);

    let data = if let Some(refresh_token) = google_refresh_token {
        let access_token = refresh_google_access_token(refresh_token, config).await?;
        call_gemini_via_cloudcode(&access_token, model, &contents, &system_parts, max_tokens, temperature).await?
    } else if !config.gemini_api_key.is_empty() {
        let url = format!("{GEMINI_BASE_URL}/{model}:generateContent?key={}", config.gemini_api_key);
        let mut payload = json!({
            "contents": contents,
            "generationConfig": {
                "maxOutputTokens": max_tokens,
                "temperature": temperature,
            },
        });
        if !system_parts.is_empty() {
            payload.as_object_mut().unwrap().insert(
                "systemInstruction".into(),
                json!({ "role": "user", "parts": system_parts }),
            );
        }

        let client = reqwest::Client::new();
        let resp = client
            .post(&url)
            .json(&payload)
            .timeout(std::time::Duration::from_secs(60))
            .send()
            .await
            .map_err(|e| format!("Gemini API error: {e}"))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::error!("Gemini API error {status}: {text}");
            return Err(format!("Gemini API error: {status}"));
        }

        resp.json::<Value>().await.map_err(|e| format!("Failed to parse Gemini response: {e}"))?
    } else {
        return Err("No Gemini credentials available".into());
    };

    let content = data
        .pointer("/candidates/0/content/parts/0/text")
        .and_then(|v| v.as_str())
        .ok_or_else(|| {
            tracing::error!("Unexpected Gemini response: {data}");
            format!("Unexpected Gemini response format")
        })?
        .to_string();

    let usage_meta = data.get("usageMetadata").cloned().unwrap_or(json!({}));
    Ok(LlmResponse {
        content,
        provider: "gemini".into(),
        model: model.to_string(),
        usage: json!({
            "prompt_tokens": usage_meta.get("promptTokenCount").and_then(|v| v.as_i64()).unwrap_or(0),
            "completion_tokens": usage_meta.get("candidatesTokenCount").and_then(|v| v.as_i64()).unwrap_or(0),
            "total_tokens": usage_meta.get("totalTokenCount").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
    })
}

pub fn parse_gemini_model_list(data: &Value) -> Vec<Value> {
    let mut models: Vec<Value> = data
        .get("models")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|m| {
                    let name = m.get("name")?.as_str()?;
                    let model_id = name.strip_prefix("models/").unwrap_or(name);
                    let methods = m
                        .get("supportedGenerationMethods")
                        .and_then(|v| v.as_array())?;
                    if methods
                        .iter()
                        .any(|v| v.as_str() == Some("generateContent"))
                    {
                        Some(json!({"id": model_id, "owned_by": "google"}))
                    } else {
                        None
                    }
                })
                .collect()
        })
        .unwrap_or_default();

    models.sort_by(|a, b| {
        let a_id = a.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let b_id = b.get("id").and_then(|v| v.as_str()).unwrap_or("");
        a_id.cmp(b_id)
    });
    models
}

pub async fn list_gemini_models(
    google_refresh_token: Option<&str>,
    config: &Config,
) -> Vec<Value> {
    if let Some(refresh_token) = google_refresh_token {
        if let Ok(access_token) = refresh_google_access_token(refresh_token, config).await {
            let client = reqwest::Client::new();
            if let Ok(resp) = client
                .get(GEMINI_BASE_URL)
                .bearer_auth(&access_token)
                .timeout(std::time::Duration::from_secs(10))
                .send()
                .await
            {
                if resp.status().is_success() {
                    if let Ok(data) = resp.json::<Value>().await {
                        let models = parse_gemini_model_list(&data);
                        if !models.is_empty() {
                            return models;
                        }
                    }
                }
            }
        }
    }

    if !config.gemini_api_key.is_empty() {
        let client = reqwest::Client::new();
        let url = format!("{GEMINI_BASE_URL}?key={}", config.gemini_api_key);
        if let Ok(resp) = client
            .get(&url)
            .timeout(std::time::Duration::from_secs(10))
            .send()
            .await
        {
            if resp.status().is_success() {
                if let Ok(data) = resp.json::<Value>().await {
                    let models = parse_gemini_model_list(&data);
                    if !models.is_empty() {
                        return models;
                    }
                }
            }
        }
    }

    // Fallback known models
    vec![
        json!({"id": "gemini-3-flash-preview", "owned_by": "google"}),
        json!({"id": "gemini-3-pro-preview", "owned_by": "google"}),
        json!({"id": "gemini-2.5-pro", "owned_by": "google"}),
        json!({"id": "gemini-2.5-flash", "owned_by": "google"}),
    ]
}
