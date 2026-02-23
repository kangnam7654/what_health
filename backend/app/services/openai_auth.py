import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)

OPENAI_TOKEN_URL = "https://auth.openai.com/oauth/token"
OPENAI_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
OPENAI_USERINFO_URL = "https://api.openai.com/v1/me"


async def exchange_chatgpt_auth_code(
    authorization_code: str,
    redirect_uri: str,
    code_verifier: str,
) -> dict[str, Any]:
    """Exchange a ChatGPT PKCE authorization code for tokens and user info."""
    token_data = {
        "grant_type": "authorization_code",
        "code": authorization_code,
        "redirect_uri": redirect_uri,
        "client_id": OPENAI_CLIENT_ID,
        "code_verifier": code_verifier,
    }

    async with httpx.AsyncClient(timeout=15.0) as client:
        token_response = await client.post(OPENAI_TOKEN_URL, data=token_data)
        if token_response.status_code != 200:
            logger.error("ChatGPT token exchange failed: %s", token_response.text)
            raise ValueError(f"ChatGPT token exchange failed: {token_response.status_code}")

        tokens = token_response.json()
        access_token = tokens.get("access_token")
        if not access_token:
            raise ValueError("No access token in ChatGPT response")

        # Fetch user info
        userinfo_response = await client.get(
            OPENAI_USERINFO_URL,
            headers={"Authorization": f"Bearer {access_token}"},
        )

    # Extract sub/email from id_token if present, otherwise from userinfo
    id_token_raw = tokens.get("id_token")
    sub = None
    email = None

    if id_token_raw:
        # Decode JWT payload (no verification needed — we trust the token endpoint)
        import base64
        import json

        parts = id_token_raw.split(".")
        if len(parts) >= 2:
            payload_b64 = parts[1] + "=" * (-len(parts[1]) % 4)
            try:
                payload = json.loads(base64.urlsafe_b64decode(payload_b64))
                sub = payload.get("sub")
                email = payload.get("email")
            except Exception:
                logger.warning("Failed to decode ChatGPT id_token payload")

    # Fallback: use userinfo endpoint
    if not sub and userinfo_response.status_code == 200:
        userinfo = userinfo_response.json()
        sub = userinfo.get("id") or userinfo.get("sub")
        email = email or userinfo.get("email")

    if not sub:
        raise ValueError("Could not determine user identity from ChatGPT token response")

    return {
        "sub": sub,
        "email": email,
        "access_token": access_token,
        "refresh_token": tokens.get("refresh_token"),
    }
