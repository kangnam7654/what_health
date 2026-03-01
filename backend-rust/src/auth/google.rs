use serde::Deserialize;

use crate::config::Config;

const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const GOOGLE_USERINFO_URL: &str = "https://www.googleapis.com/oauth2/v3/userinfo";

#[derive(Debug, Deserialize)]
struct GoogleTokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GoogleUserInfo {
    sub: Option<String>,
    email: Option<String>,
    email_verified: Option<bool>,
    name: Option<String>,
}

pub struct GoogleAuthData {
    pub sub: String,
    pub email: Option<String>,
    pub email_verified: bool,
    pub name: Option<String>,
    pub refresh_token: Option<String>,
}

pub async fn exchange_google_auth_code(
    authorization_code: &str,
    redirect_uri: &str,
    config: &Config,
) -> Result<GoogleAuthData, String> {
    let client = reqwest::Client::new();

    let params = [
        ("code", authorization_code),
        ("client_id", &config.google_client_id),
        ("client_secret", &config.google_client_secret),
        ("redirect_uri", redirect_uri),
        ("grant_type", "authorization_code"),
    ];

    let token_resp = client
        .post(GOOGLE_TOKEN_URL)
        .form(&params)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("Google token exchange failed: {e}"))?;

    if !token_resp.status().is_success() {
        let text = token_resp.text().await.unwrap_or_default();
        tracing::error!("Google token exchange failed: {text}");
        return Err(format!(
            "Google token exchange failed: {text}"
        ));
    }

    let tokens: GoogleTokenResponse = token_resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse Google token response: {e}"))?;

    let access_token = tokens
        .access_token
        .ok_or("No access token in Google response")?;

    let userinfo_resp = client
        .get(GOOGLE_USERINFO_URL)
        .bearer_auth(&access_token)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch Google user info: {e}"))?;

    if !userinfo_resp.status().is_success() {
        return Err("Failed to fetch Google user info".into());
    }

    let userinfo: GoogleUserInfo = userinfo_resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse Google user info: {e}"))?;

    let sub = userinfo.sub.ok_or("Google user info missing 'sub' field")?;

    Ok(GoogleAuthData {
        sub,
        email: userinfo.email,
        email_verified: userinfo.email_verified.unwrap_or(false),
        name: userinfo.name,
        refresh_token: tokens.refresh_token,
    })
}
