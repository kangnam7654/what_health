from typing import Literal

from pydantic import BaseModel


class Message(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str


class LLMProxyRequest(BaseModel):
    messages: list[Message]
    provider: Literal["openai", "gemini", "codex"] = "openai"
    model: str | None = None
    max_tokens: int = 2048
    temperature: float = 0.7


class LLMProxyResponse(BaseModel):
    content: str
    provider: str
    model: str
    usage: dict[str, int] | None = None
