import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.chat import LLMProxyRequest, LLMProxyResponse
from app.services.llm_proxy import proxy_llm_request
from app.services.quota_service import decrement_quota

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["llm"])


async def _handle_llm_request(
    body: LLMProxyRequest,
    current_user: User,
    db: AsyncSession,
) -> LLMProxyResponse:
    allowed = await decrement_quota(db, current_user.id)
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily quota exceeded. Please upgrade your plan or try again tomorrow.",
        )

    try:
        return await proxy_llm_request(
            body,
            google_refresh_token=current_user.google_refresh_token,
            openai_refresh_token=current_user.openai_refresh_token,
        )
    except ValueError as exc:
        logger.error("LLM proxy error for user %d: %s", current_user.id, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc


@router.post("/chat", response_model=LLMProxyResponse)
async def chat(
    body: LLMProxyRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> LLMProxyResponse:
    return await _handle_llm_request(body, current_user, db)


@router.post("/generate-plan", response_model=LLMProxyResponse)
async def generate_plan(
    body: LLMProxyRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> LLMProxyResponse:
    return await _handle_llm_request(body, current_user, db)
