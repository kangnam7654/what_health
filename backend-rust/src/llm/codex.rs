use serde_json::{json, Value};

use crate::auth::jwt::decode_jwt_payload;
use crate::config::Config;

const CHATGPT_RESPONSES_URL: &str = "https://chatgpt.com/backend-api/codex/responses";
const CHATGPT_TOKEN_REFRESH_URL: &str = "https://chatgpt.com/backend-api/token";
const OPENAI_CHAT_URL: &str = "https://api.openai.com/v1/chat/completions";

use super::openai::LlmResponse;

fn extract_account_id_from_jwt(access_token: &str) -> Option<String> {
    let payload = decode_jwt_payload(access_token)?;
    payload
        .get("account_id")
        .and_then(|v| v.as_str())
        .map(String::from)
        .or_else(|| {
            payload
                .pointer("/https:~1~1api.openai.com~1auth/account_id")
                .and_then(|v| v.as_str())
                .map(String::from)
        })
        .or_else(|| {
            payload
                .get("org_id")
                .and_then(|v| v.as_str())
                .map(String::from)
        })
}

pub async fn refresh_openai_token(refresh_token: &str) -> Result<String, String> {
    refresh_openai_access_token(refresh_token).await
}

async fn refresh_openai_access_token(refresh_token: &str) -> Result<String, String> {
    let client = reqwest::Client::new();
    let resp = client
        .post(CHATGPT_TOKEN_REFRESH_URL)
        .json(&json!({"refresh_token": refresh_token}))
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("ChatGPT token refresh failed: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        tracing::error!("ChatGPT token refresh failed: {text}");
        return Err(format!("ChatGPT token refresh failed: {status}"));
    }

    let data: Value = resp.json().await.map_err(|e| format!("Failed to parse token response: {e}"))?;
    data.get("access_token")
        .or_else(|| data.get("token"))
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| "No token in ChatGPT refresh response".into())
}

fn messages_to_responses_api_input(messages: &[Value]) -> (Option<String>, Vec<Value>) {
    let mut system_parts: Vec<String> = Vec::new();
    let mut input_items: Vec<Value> = Vec::new();

    for msg in messages {
        let role = msg.get("role").and_then(|v| v.as_str()).unwrap_or("");
        let content = msg.get("content").and_then(|v| v.as_str()).unwrap_or("");

        if role == "system" {
            system_parts.push(content.to_string());
        } else {
            input_items.push(json!({
                "role": role,
                "content": content,
            }));
        }
    }

    let instructions = if system_parts.is_empty() {
        None
    } else {
        Some(system_parts.join("\n"))
    };

    (instructions, input_items)
}

async fn call_responses_api(
    access_token: &str,
    model: &str,
    instructions: Option<&str>,
    input_items: &[Value],
) -> Result<(u16, Value), String> {
    let mut payload = json!({
        "model": model,
        "input": input_items,
        "store": false,
        "stream": true,
    });
    if let Some(inst) = instructions {
        payload
            .as_object_mut()
            .unwrap()
            .insert("instructions".into(), json!(inst));
    }

    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert("Content-Type", "application/json".parse().unwrap());
    headers.insert("Accept", "text/event-stream".parse().unwrap());

    if let Some(account_id) = extract_account_id_from_jwt(access_token) {
        if let Ok(val) = account_id.parse() {
            headers.insert("ChatGPT-Account-Id", val);
        }
    }

    let client = reqwest::Client::new();
    let resp = client
        .post(CHATGPT_RESPONSES_URL)
        .bearer_auth(access_token)
        .headers(headers)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(90))
        .send()
        .await
        .map_err(|e| format!("Codex API error: {e}"))?;

    let status = resp.status().as_u16();
    if status != 200 {
        let text = resp.text().await.unwrap_or_default();
        return Ok((status, json!({"error": text})));
    }

    // Process SSE stream
    let body = resp.text().await.map_err(|e| format!("Failed to read SSE stream: {e}"))?;
    let mut collected_text = String::new();
    let mut last_json_data: Option<Value> = None;

    for line in body.lines() {
        if !line.starts_with("data: ") {
            continue;
        }
        let data_str = &line[6..];
        if data_str == "[DONE]" {
            break;
        }
        if let Ok(event_data) = serde_json::from_str::<Value>(data_str) {
            last_json_data = Some(event_data.clone());
            if event_data.get("type").and_then(|v| v.as_str()) == Some("response.output_text.delta")
            {
                if let Some(delta) = event_data.get("delta").and_then(|v| v.as_str()) {
                    collected_text.push_str(delta);
                }
            }
        }
    }

    let final_response = if let Some(ref last) = last_json_data {
        if last.get("type").and_then(|v| v.as_str()) == Some("response.completed") {
            last.get("response").cloned().unwrap_or(json!({}))
        } else {
            json!({
                "output": [{
                    "type": "message",
                    "content": [{"type": "output_text", "text": collected_text}],
                }],
                "usage": {},
            })
        }
    } else {
        json!({
            "output": [{
                "type": "message",
                "content": [{"type": "output_text", "text": collected_text}],
            }],
            "usage": {},
        })
    };

    Ok((200, final_response))
}

async fn call_codex_via_oauth(
    messages: &[Value],
    model: &str,
    openai_access_token: Option<&str>,
    openai_refresh_token: Option<&str>,
) -> Result<LlmResponse, String> {
    let (instructions, input_items) = messages_to_responses_api_input(messages);

    let mut response: Option<(u16, Value)> = None;

    if let Some(access_token) = openai_access_token {
        let r = call_responses_api(access_token, model, instructions.as_deref(), &input_items).await?;
        tracing::info!("Codex initial response: {}", r.0);
        response = Some(r);
    }

    let needs_refresh = response.is_none()
        || matches!(response.as_ref(), Some((status, _)) if *status == 401 || *status == 403);

    if needs_refresh {
        if let Some(refresh_token) = openai_refresh_token {
            tracing::info!("Refreshing ChatGPT token via {CHATGPT_TOKEN_REFRESH_URL}");
            let refreshed_token = refresh_openai_access_token(refresh_token).await?;
            let r = call_responses_api(&refreshed_token, model, instructions.as_deref(), &input_items).await?;
            tracing::info!("Codex after refresh: {}", r.0);
            response = Some(r);
        } else if let Some((status, _)) = &response {
            tracing::error!(
                "Codex Responses API {status} and no refresh token available"
            );
            return Err(format!("Codex API error: {status} (no refresh token)"));
        }
    }

    let (status, data) = response.ok_or("No response from Codex API")?;
    if status != 200 {
        let text = data
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        tracing::error!("Codex Responses API error {status}: {text}");
        return Err(format!("Codex API error: {status}"));
    }

    // Extract text from Responses API output
    let mut content = String::new();
    if let Some(output) = data.get("output").and_then(|v| v.as_array()) {
        for item in output {
            if item.get("type").and_then(|v| v.as_str()) == Some("message") {
                if let Some(parts) = item.get("content").and_then(|v| v.as_array()) {
                    for part in parts {
                        if part.get("type").and_then(|v| v.as_str()) == Some("output_text") {
                            if let Some(text) = part.get("text").and_then(|v| v.as_str()) {
                                content.push_str(text);
                            }
                        }
                    }
                }
            }
        }
    }

    if content.is_empty() {
        tracing::error!("Codex Responses API returned no text content: {data}");
        return Err("Codex returned no text content".into());
    }

    let usage = data.get("usage").cloned().unwrap_or(json!({}));
    let input_tokens = usage.get("input_tokens").and_then(|v| v.as_i64()).unwrap_or(0);
    let output_tokens = usage.get("output_tokens").and_then(|v| v.as_i64()).unwrap_or(0);

    Ok(LlmResponse {
        content,
        provider: "codex".into(),
        model: model.to_string(),
        usage: json!({
            "prompt_tokens": input_tokens,
            "completion_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
        }),
    })
}

async fn call_codex_via_api_key(
    messages: &[Value],
    model: &str,
    config: &Config,
) -> Result<LlmResponse, String> {
    let payload = json!({
        "model": model,
        "messages": messages,
        "max_tokens": 2048,
        "temperature": 0.7,
    });

    let client = reqwest::Client::new();
    let resp = client
        .post(OPENAI_CHAT_URL)
        .bearer_auth(&config.openai_api_key)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(60))
        .send()
        .await
        .map_err(|e| format!("Codex API error: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        tracing::error!("Codex API error {status}: {text}");
        return Err(format!("Codex API error: {status}"));
    }

    let data: Value = resp.json().await.map_err(|e| format!("Failed to parse Codex response: {e}"))?;

    let content = data["choices"][0]["message"]["content"]
        .as_str()
        .unwrap_or("")
        .to_string();

    let usage = data.get("usage").cloned().unwrap_or(json!({}));

    Ok(LlmResponse {
        content,
        provider: "codex".into(),
        model: model.to_string(),
        usage: json!({
            "prompt_tokens": usage.get("prompt_tokens").and_then(|v| v.as_i64()).unwrap_or(0),
            "completion_tokens": usage.get("completion_tokens").and_then(|v| v.as_i64()).unwrap_or(0),
            "total_tokens": usage.get("total_tokens").and_then(|v| v.as_i64()).unwrap_or(0),
        }),
    })
}

pub async fn call_codex(
    messages: &[Value],
    model: Option<&str>,
    openai_access_token: Option<&str>,
    openai_refresh_token: Option<&str>,
    config: &Config,
) -> Result<LlmResponse, String> {
    let model = model.unwrap_or(&config.codex_default_model);

    if openai_access_token.is_some() || openai_refresh_token.is_some() {
        call_codex_via_oauth(messages, model, openai_access_token, openai_refresh_token).await
    } else if !config.openai_api_key.is_empty() {
        call_codex_via_api_key(messages, model, config).await
    } else {
        Err("No Codex credentials available (neither ChatGPT OAuth nor API key)".into())
    }
}
