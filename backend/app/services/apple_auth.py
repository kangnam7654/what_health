import logging
from typing import Any

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey

from app.config import settings

logger = logging.getLogger(__name__)

APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"


async def _fetch_apple_public_keys() -> list[dict[str, Any]]:
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(APPLE_KEYS_URL)
        response.raise_for_status()
        data = response.json()
        return data.get("keys", [])


def _find_matching_key(keys: list[dict[str, Any]], kid: str) -> dict[str, Any] | None:
    for key in keys:
        if key.get("kid") == kid:
            return key
    return None


async def verify_apple_identity_token(identity_token: str) -> dict[str, Any]:
    try:
        header = jwt.get_unverified_header(identity_token)
        kid = header.get("kid")
        if not kid:
            raise ValueError("Missing kid in token header")

        keys = await _fetch_apple_public_keys()
        key_data = _find_matching_key(keys, kid)
        if not key_data:
            raise ValueError(f"No matching Apple public key for kid={kid}")

        public_key = jwt.algorithms.RSAAlgorithm.from_jwk(key_data)

        payload = jwt.decode(
            identity_token,
            public_key,  # type: ignore[arg-type]
            algorithms=["RS256"],
            audience=settings.apple_bundle_id,
            issuer=APPLE_ISSUER,
        )

        return {
            "sub": payload["sub"],
            "email": payload.get("email"),
            "email_verified": payload.get("email_verified", False),
        }

    except jwt.ExpiredSignatureError:
        raise ValueError("Apple identity token has expired")
    except jwt.InvalidTokenError as exc:
        raise ValueError(f"Invalid Apple identity token: {exc}") from exc
