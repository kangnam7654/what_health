import logging
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"


async def exchange_google_auth_code(authorization_code: str, redirect_uri: str) -> dict[str, Any]:
    token_data: dict[str, str] = {
        "code": authorization_code,
        "client_id": settings.google_client_id,
        "client_secret": settings.google_client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }

    async with httpx.AsyncClient(timeout=15.0) as client:
        token_response = await client.post(GOOGLE_TOKEN_URL, data=token_data)
        if token_response.status_code != 200:
            logger.error("Google token exchange failed: %s", token_response.text)
            raise ValueError(f"Google token exchange failed: {token_response.status_code}")

        tokens = token_response.json()
        access_token = tokens.get("access_token")
        if not access_token:
            raise ValueError("No access token in Google response")

        userinfo_response = await client.get(
            GOOGLE_USERINFO_URL,
            headers={"Authorization": f"Bearer {access_token}"},
        )
        if userinfo_response.status_code != 200:
            raise ValueError("Failed to fetch Google user info")

        userinfo = userinfo_response.json()

    sub = userinfo.get("sub")
    if not sub:
        raise ValueError("Google user info missing 'sub' field")

    return {
        "sub": sub,
        "email": userinfo.get("email"),
        "email_verified": userinfo.get("email_verified", False),
        "name": userinfo.get("name"),
        "refresh_token": tokens.get("refresh_token"),
    }
