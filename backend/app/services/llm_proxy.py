import logging
import platform
from typing import Any

import httpx

from app.config import settings
from app.schemas.chat import LLMProxyRequest, LLMProxyResponse, Message
from app.services.openai_auth import OPENAI_TOKEN_URL, OPENAI_CLIENT_ID as OPENAI_OAUTH_CLIENT_ID

logger = logging.getLogger(__name__)

OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
OPENAI_DEFAULT_MODEL = "gpt-4o-mini"

# OpenAI Responses API (used with ChatGPT OAuth)
OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"

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


async def _refresh_openai_access_token(refresh_token: str) -> str:
    """Exchange an OpenAI refresh token for a new access token."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            OPENAI_TOKEN_URL,
            data={
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": OPENAI_OAUTH_CLIENT_ID,
            },
        )
        if resp.status_code != 200:
            logger.error("OpenAI token refresh failed: %s", resp.text)
            raise ValueError(f"OpenAI token refresh failed: {resp.status_code}")
        return resp.json()["access_token"]


def _messages_to_responses_api_input(
    messages: list[Message],
) -> tuple[str | None, list[dict[str, Any]]]:
    """Convert chat messages to OpenAI Responses API format.

    Returns (system_instructions, input_messages).
    """
    system_parts: list[str] = []
    input_items: list[dict[str, Any]] = []

    for msg in messages:
        if msg.role == "system":
            system_parts.append(msg.content)
        else:
            input_items.append({
                "role": msg.role,
                "content": msg.content,
            })

    instructions = "\n".join(system_parts) if system_parts else None
    return instructions, input_items


async def call_codex(
    request: LLMProxyRequest,
    openai_refresh_token: str | None = None,
) -> LLMProxyResponse:
    """OpenAI Codex — OAuth (Responses API) or API key (Chat Completions) fallback."""
    model = request.model or settings.codex_default_model

    if openai_refresh_token:
        # OAuth path: Responses API
        access_token = await _refresh_openai_access_token(openai_refresh_token)

        instructions, input_items = _messages_to_responses_api_input(request.messages)
        payload: dict[str, Any] = {
            "model": model,
            "input": input_items,
        }
        if instructions:
            payload["instructions"] = instructions
        if request.temperature is not None:
            payload["temperature"] = request.temperature

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                OPENAI_RESPONSES_URL,
                json=payload,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json",
                },
            )
            if response.status_code != 200:
                logger.error("Codex Responses API error %d: %s", response.status_code, response.text)
                raise ValueError(f"Codex API error: {response.status_code}")

            data = response.json()

        # Extract text from Responses API output
        content = ""
        for item in data.get("output", []):
            if item.get("type") == "message":
                for part in item.get("content", []):
                    if part.get("type") == "output_text":
                        content += part.get("text", "")

        if not content:
            logger.error("Codex Responses API returned no text content: %s", data)
            raise ValueError("Codex returned no text content")

        usage = data.get("usage", {})
        return LLMProxyResponse(
            content=content,
            provider="codex",
            model=model,
            usage={
                "prompt_tokens": usage.get("input_tokens", 0),
                "completion_tokens": usage.get("output_tokens", 0),
                "total_tokens": usage.get("input_tokens", 0) + usage.get("output_tokens", 0),
            },
        )

    elif settings.openai_api_key:
        # Fallback: server API key → Chat Completions API
        payload_cc = {
            "model": model,
            "messages": [{"role": m.role, "content": m.content} for m in request.messages],
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
        }

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                OPENAI_CHAT_URL,
                json=payload_cc,
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json",
                },
            )
            if response.status_code != 200:
                logger.error("Codex API error %d: %s", response.status_code, response.text)
                raise ValueError(f"Codex API error: {response.status_code}")

            data = response.json()

        content = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})

        return LLMProxyResponse(
            content=content,
            provider="codex",
            model=model,
            usage={
                "prompt_tokens": usage.get("prompt_tokens", 0),
                "completion_tokens": usage.get("completion_tokens", 0),
                "total_tokens": usage.get("total_tokens", 0),
            },
        )

    else:
        raise ValueError("No Codex credentials available (neither ChatGPT OAuth nor API key)")


async def proxy_llm_request(
    request: LLMProxyRequest,
    google_refresh_token: str | None = None,
    openai_refresh_token: str | None = None,
) -> LLMProxyResponse:
    if request.provider == "gemini":
        return await call_gemini(request, google_refresh_token=google_refresh_token)
    elif request.provider == "codex":
        return await call_codex(request, openai_refresh_token=openai_refresh_token)
    return await call_openai(request)
