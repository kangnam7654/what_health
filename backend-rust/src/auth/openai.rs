use serde::Deserialize;

use crate::auth::jwt::decode_jwt_payload;

const OPENAI_TOKEN_URL: &str = "https://auth.openai.com/oauth/token";
const OPENAI_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
const OPENAI_USERINFO_URL: &str = "https://api.openai.com/v1/me";

#[derive(Debug, Deserialize)]
struct OpenAITokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
    id_token: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAIUserInfo {
    id: Option<String>,
    sub: Option<String>,
    email: Option<String>,
}

pub struct ChatGPTAuthData {
    pub sub: String,
    pub email: Option<String>,
    pub access_token: String,
    pub refresh_token: Option<String>,
}

pub async fn exchange_chatgpt_auth_code(
    authorization_code: &str,
    redirect_uri: &str,
    code_verifier: &str,
) -> Result<ChatGPTAuthData, String> {
    let client = reqwest::Client::new();

    let params = [
        ("grant_type", "authorization_code"),
        ("code", authorization_code),
        ("redirect_uri", redirect_uri),
        ("client_id", OPENAI_CLIENT_ID),
        ("code_verifier", code_verifier),
    ];

    let token_resp = client
        .post(OPENAI_TOKEN_URL)
        .form(&params)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("ChatGPT token exchange failed: {e}"))?;

    if !token_resp.status().is_success() {
        let text = token_resp.text().await.unwrap_or_default();
        tracing::error!("ChatGPT token exchange failed: {text}");
        return Err(format!("ChatGPT token exchange failed: {text}"));
    }

    let tokens: OpenAITokenResponse = token_resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse ChatGPT token response: {e}"))?;

    let access_token = tokens
        .access_token
        .ok_or("No access token in ChatGPT response")?;

    // Fetch user info
    let userinfo_resp = client
        .get(OPENAI_USERINFO_URL)
        .bearer_auth(&access_token)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await;

    // Extract sub/email from id_token if present
    let mut sub: Option<String> = None;
    let mut email: Option<String> = None;

    if let Some(ref id_token) = tokens.id_token {
        if let Some(payload) = decode_jwt_payload(id_token) {
            sub = payload.get("sub").and_then(|v| v.as_str()).map(String::from);
            email = payload
                .get("email")
                .and_then(|v| v.as_str())
                .map(String::from);
        } else {
            tracing::warn!("Failed to decode ChatGPT id_token payload");
        }
    }

    // Fallback: use userinfo endpoint
    if sub.is_none() {
        if let Ok(resp) = userinfo_resp {
            if resp.status().is_success() {
                if let Ok(userinfo) = resp.json::<OpenAIUserInfo>().await {
                    sub = userinfo.id.or(userinfo.sub);
                    if email.is_none() {
                        email = userinfo.email;
                    }
                }
            }
        }
    }

    let sub = sub.ok_or("Could not determine user identity from ChatGPT token response")?;

    Ok(ChatGPTAuthData {
        sub,
        email,
        access_token,
        refresh_token: tokens.refresh_token,
    })
}
