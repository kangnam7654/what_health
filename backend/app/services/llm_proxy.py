import logging
import platform
from typing import Any

import httpx

from app.config import settings
from app.schemas.chat import LLMProxyRequest, LLMProxyResponse, Message

logger = logging.getLogger(__name__)

OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
OPENAI_DEFAULT_MODEL = "gpt-4o-mini"

# Gemini CLI uses the Cloud Code Private API, NOT generativelanguage.googleapis.com
CLOUDCODE_BASE_URL = "https://cloudcode-pa.googleapis.com"
CLOUDCODE_API_VERSION = "v1internal"

# Fallback: standard Gemini API (requires API key)
GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"
GEMINI_DEFAULT_MODEL = "gemini-2.0-flash"

_USER_AGENT = f"GeminiCLI/0.1.5 ({platform.system()}; {platform.machine()})"


def _messages_to_gemini_contents(messages: list[Message]) -> list[dict[str, Any]]:
    contents = []
    system_parts: list[dict[str, str]] = []

    for msg in messages:
        if msg.role == "system":
            system_parts.append({"text": msg.content})
            continue
        role = "user" if msg.role == "user" else "model"
        contents.append({
            "role": role,
            "parts": [{"text": msg.content}],
        })

    return contents, system_parts


# ---------------------------------------------------------------------------
# Google OAuth token refresh
# ---------------------------------------------------------------------------

async def _refresh_google_access_token(refresh_token: str) -> str:
    """Exchange a Google refresh token for a new access token."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            "https://oauth2.googleapis.com/token",
            data={
                "client_id": settings.google_client_id,
                "client_secret": settings.google_client_secret,
                "refresh_token": refresh_token,
                "grant_type": "refresh_token",
            },
        )
        if resp.status_code != 200:
            logger.error("Google token refresh failed: %s", resp.text)
            raise ValueError(f"Google token refresh failed: {resp.status_code}")
        return resp.json()["access_token"]


# ---------------------------------------------------------------------------
# Cloud Code Private API helpers (Gemini CLI compatible)
# ---------------------------------------------------------------------------

async def _cloudcode_load_project(access_token: str) -> str:
    """Discover the user's GCP project via loadCodeAssist."""
    url = f"{CLOUDCODE_BASE_URL}/{CLOUDCODE_API_VERSION}:loadCodeAssist"
    payload = {
        "metadata": {
            "ideType": "IDE_UNSPECIFIED",
            "platform": f"{platform.system().upper()}_{platform.machine().upper()}",
            "pluginType": "GEMINI",
            "duetProject": None,
        }
    }
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(url, json=payload, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "User-Agent": _USER_AGENT,
        })
        if resp.status_code != 200:
            logger.error("loadCodeAssist failed %d: %s", resp.status_code, resp.text)
            raise ValueError(f"loadCodeAssist failed: {resp.status_code}")
        data = resp.json()

    project = data.get("cloudaicompanionProject")
    if not project:
        raise ValueError("No cloudaicompanionProject in loadCodeAssist response")
    return project


async def _call_gemini_via_cloudcode(
    access_token: str,
    model: str,
    contents: list[dict[str, Any]],
    system_parts: list[dict[str, str]],
    max_tokens: int,
    temperature: float,
) -> dict[str, Any]:
    """Call Gemini via the Cloud Code Private API (same as Gemini CLI)."""
    # 1. Discover project
    project = await _cloudcode_load_project(access_token)

    # 2. Build wrapped request
    inner_request: dict[str, Any] = {
        "contents": contents,
        "generationConfig": {
            "maxOutputTokens": max_tokens,
            "temperature": temperature,
        },
    }
    if system_parts:
        inner_request["systemInstruction"] = {
            "role": "user",
            "parts": system_parts,
        }

    payload = {
        "model": model,
        "project": project,
        "request": inner_request,
    }

    # 3. Call generateContent
    url = f"{CLOUDCODE_BASE_URL}/{CLOUDCODE_API_VERSION}:generateContent"
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(url, json=payload, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "User-Agent": _USER_AGENT,
        })
        if resp.status_code != 200:
            logger.error("CloudCode generateContent %d: %s", resp.status_code, resp.text)
            raise ValueError(f"Gemini API error: {resp.status_code}")

        data = resp.json()

    # 4. Unwrap response (response is nested inside "response" key)
    return data.get("response", data)


# ---------------------------------------------------------------------------
# OpenAI
# ---------------------------------------------------------------------------

async def call_openai(request: LLMProxyRequest) -> LLMProxyResponse:
    if not settings.openai_api_key:
        raise ValueError("OpenAI API key not configured")

    model = request.model or OPENAI_DEFAULT_MODEL
    payload = {
        "model": model,
        "messages": [{"role": m.role, "content": m.content} for m in request.messages],
        "max_tokens": request.max_tokens,
        "temperature": request.temperature,
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            OPENAI_CHAT_URL,
            json=payload,
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
        )
        if response.status_code != 200:
            logger.error("OpenAI API error %d: %s", response.status_code, response.text)
            raise ValueError(f"OpenAI API error: {response.status_code}")

        data = response.json()

    content = data["choices"][0]["message"]["content"]
    usage = data.get("usage", {})

    return LLMProxyResponse(
        content=content,
        provider="openai",
        model=model,
        usage={
            "prompt_tokens": usage.get("prompt_tokens", 0),
            "completion_tokens": usage.get("completion_tokens", 0),
            "total_tokens": usage.get("total_tokens", 0),
        },
    )


# ---------------------------------------------------------------------------
# Gemini (OAuth via CloudCode or API key fallback)
# ---------------------------------------------------------------------------

async def call_gemini(
    request: LLMProxyRequest,
    google_refresh_token: str | None = None,
) -> LLMProxyResponse:
    model = request.model or GEMINI_DEFAULT_MODEL
    contents, system_parts = _messages_to_gemini_contents(request.messages)

    if google_refresh_token:
        # Primary: user OAuth → Cloud Code Private API (free quota)
        access_token = await _refresh_google_access_token(google_refresh_token)
        data = await _call_gemini_via_cloudcode(
            access_token, model, contents, system_parts,
            request.max_tokens, request.temperature,
        )
    elif settings.gemini_api_key:
        # Fallback: server API key → standard Gemini API
        url = f"{GEMINI_BASE_URL}/{model}:generateContent?key={settings.gemini_api_key}"
        payload: dict[str, Any] = {
            "contents": contents,
            "generationConfig": {
                "maxOutputTokens": request.max_tokens,
                "temperature": request.temperature,
            },
        }
        if system_parts:
            payload["systemInstruction"] = {"role": "user", "parts": system_parts}

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(url, json=payload)
            if response.status_code != 200:
                logger.error("Gemini API error %d: %s", response.status_code, response.text)
                raise ValueError(f"Gemini API error: {response.status_code}")
            data = response.json()
    else:
        raise ValueError("No Gemini credentials available")

    try:
        content = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError) as exc:
        logger.error("Unexpected Gemini response: %s", data)
        raise ValueError(f"Unexpected Gemini response format: {exc}") from exc

    usage_meta = data.get("usageMetadata", {})
    return LLMProxyResponse(
        content=content,
        provider="gemini",
        model=model,
        usage={
            "prompt_tokens": usage_meta.get("promptTokenCount", 0),
            "completion_tokens": usage_meta.get("candidatesTokenCount", 0),
            "total_tokens": usage_meta.get("totalTokenCount", 0),
        },
    )


async def proxy_llm_request(
    request: LLMProxyRequest,
    google_refresh_token: str | None = None,
) -> LLMProxyResponse:
    if request.provider == "gemini":
        return await call_gemini(request, google_refresh_token=google_refresh_token)
    return await call_openai(request)
