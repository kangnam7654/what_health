use jsonwebtoken::{decode, Algorithm, DecodingKey, Validation};
use serde::{Deserialize, Serialize};

use crate::config::Config;

const APPLE_KEYS_URL: &str = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER: &str = "https://appleid.apple.com";

#[derive(Debug, Deserialize)]
struct AppleJwks {
    keys: Vec<AppleJwk>,
}

#[derive(Debug, Deserialize)]
struct AppleJwk {
    kid: String,
    kty: String,
    n: String,
    e: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct AppleClaims {
    sub: String,
    email: Option<String>,
    email_verified: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct JwtHeader {
    kid: Option<String>,
}

pub struct AppleTokenData {
    pub sub: String,
    pub email: Option<String>,
    pub email_verified: bool,
}

pub async fn verify_apple_identity_token(
    identity_token: &str,
    config: &Config,
) -> Result<AppleTokenData, String> {
    // Decode header to get kid
    let header = jsonwebtoken::decode_header(identity_token)
        .map_err(|e| format!("Failed to decode token header: {e}"))?;

    let kid = header
        .kid
        .ok_or_else(|| "Missing kid in token header".to_string())?;

    // Fetch Apple's public keys
    let client = reqwest::Client::new();
    let jwks: AppleJwks = client
        .get(APPLE_KEYS_URL)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch Apple keys: {e}"))?
        .json()
        .await
        .map_err(|e| format!("Failed to parse Apple keys: {e}"))?;

    // Find matching key
    let jwk = jwks
        .keys
        .iter()
        .find(|k| k.kid == kid)
        .ok_or_else(|| format!("No matching Apple public key for kid={kid}"))?;

    // Build decoding key from RSA components
    let decoding_key = DecodingKey::from_rsa_components(&jwk.n, &jwk.e)
        .map_err(|e| format!("Failed to build RSA key: {e}"))?;

    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[&config.apple_bundle_id]);
    validation.set_issuer(&[APPLE_ISSUER]);

    let token_data = decode::<AppleClaims>(identity_token, &decoding_key, &validation)
        .map_err(|e| match e.kind() {
            jsonwebtoken::errors::ErrorKind::ExpiredSignature => {
                "Apple identity token has expired".to_string()
            }
            _ => format!("Invalid Apple identity token: {e}"),
        })?;

    let email_verified = match &token_data.claims.email_verified {
        Some(serde_json::Value::Bool(b)) => *b,
        Some(serde_json::Value::String(s)) => s == "true",
        _ => false,
    };

    Ok(AppleTokenData {
        sub: token_data.claims.sub,
        email: token_data.claims.email,
        email_verified,
    })
}
