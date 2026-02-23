import logging
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.models.subscription import Subscription, SubscriptionTier
from app.models.user import User
from app.dependencies import get_current_user
from app.schemas.auth import AppleAuthRequest, AuthResponse, AuthUserInfo, ChatGPTAuthRequest, GoogleAuthRequest, RefreshTokenRequest
from app.services.apple_auth import verify_apple_identity_token
from app.services.google_auth import exchange_google_auth_code
from app.services.openai_auth import exchange_chatgpt_auth_code
from app.services.jwt_service import (
    TOKEN_TYPE_REFRESH,
    create_access_token,
    create_refresh_token,
    verify_token,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])


async def _get_or_create_user_with_apple(
    db: AsyncSession,
    apple_sub: str,
    email: str | None,
) -> User:
    stmt = select(User).where(User.apple_user_id == apple_sub)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if user is None and email:
        stmt = select(User).where(User.email == email)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()
        if user:
            user.apple_user_id = apple_sub

    if user is None:
        user = User(apple_user_id=apple_sub, email=email)
        db.add(user)
        await db.flush()
        subscription = Subscription(user_id=user.id, tier=SubscriptionTier.FREE)
        db.add(subscription)
        await db.flush()

    return user


async def _get_or_create_user_with_google(
    db: AsyncSession,
    google_sub: str,
    email: str | None,
) -> User:
    stmt = select(User).where(User.google_user_id == google_sub)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if user is None and email:
        stmt = select(User).where(User.email == email)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()
        if user:
            user.google_user_id = google_sub

    if user is None:
        user = User(google_user_id=google_sub, email=email)
        db.add(user)
        await db.flush()
        subscription = Subscription(user_id=user.id, tier=SubscriptionTier.FREE)
        db.add(subscription)
        await db.flush()

    return user


async def _build_user_info(db: AsyncSession, user: User) -> AuthUserInfo:
    stmt = select(Subscription).where(Subscription.user_id == user.id)
    result = await db.execute(stmt)
    subscription = result.scalar_one_or_none()
    tier = subscription.tier.value if subscription else "free"
    return AuthUserInfo(
        id=str(user.id),
        email=user.email,
        display_name=user.email.split("@")[0] if user.email else None,
        subscription_tier=tier,
    )


async def _build_auth_response(db: AsyncSession, user: User) -> AuthResponse:
    user_info = await _build_user_info(db, user)
    return AuthResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
        user=user_info,
    )


@router.post("/apple", response_model=AuthResponse, status_code=status.HTTP_200_OK)
async def apple_sign_in(
    body: AppleAuthRequest,
    db: AsyncSession = Depends(get_db),
) -> AuthResponse:
    try:
        token_data = await verify_apple_identity_token(body.identity_token)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc

    apple_sub = token_data["sub"]
    email = body.email or token_data.get("email")

    user = await _get_or_create_user_with_apple(db, apple_sub, email)
    return await _build_auth_response(db, user)


@router.post("/google", response_model=AuthResponse, status_code=status.HTTP_200_OK)
async def google_sign_in(
    body: GoogleAuthRequest,
    db: AsyncSession = Depends(get_db),
) -> AuthResponse:
    try:
        user_info = await exchange_google_auth_code(body.authorization_code, body.redirect_uri)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc

    google_sub = user_info["sub"]
    email = user_info.get("email")

    user = await _get_or_create_user_with_google(db, google_sub, email)

    refresh_token = user_info.get("refresh_token")
    if refresh_token:
        user.google_refresh_token = refresh_token
        await db.flush()

    return await _build_auth_response(db, user)


@router.post("/chatgpt/connect", status_code=status.HTTP_200_OK)
async def chatgpt_connect(
    body: ChatGPTAuthRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Connect a ChatGPT account to the current user (OAuth PKCE)."""
    try:
        user_info = await exchange_chatgpt_auth_code(
            body.authorization_code, body.redirect_uri, body.code_verifier,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc

    current_user.openai_refresh_token = user_info.get("refresh_token")
    if not current_user.openai_user_id:
        current_user.openai_user_id = user_info["sub"]
    await db.flush()

    return {"status": "connected", "email": user_info.get("email")}


@router.post("/refresh", response_model=AuthResponse, status_code=status.HTTP_200_OK)
async def refresh_token(
    body: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
) -> AuthResponse:
    try:
        payload = verify_token(body.refresh_token, expected_type=TOKEN_TYPE_REFRESH)
        user_id = int(payload["sub"])
    except (ValueError, KeyError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc

    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    return await _build_auth_response(db, user)


@router.post("/dev-login", response_model=AuthResponse, status_code=status.HTTP_200_OK)
async def dev_login(db: AsyncSession = Depends(get_db)) -> AuthResponse:
    """Development-only bypass login. Creates or returns a test user."""
    email = "dev@test.com"
    stmt = select(User).where(User.email == email)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if user is None:
        user = User(email=email)
        db.add(user)
        await db.flush()
        subscription = Subscription(user_id=user.id, tier=SubscriptionTier.FREE)
        db.add(subscription)
        await db.flush()

    return await _build_auth_response(db, user)


@router.get("/me", response_model=AuthUserInfo, status_code=status.HTTP_200_OK)
async def get_me(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AuthUserInfo:
    return await _build_user_info(db, current_user)


# ---------------------------------------------------------------------------
# Browser-based Google OAuth (loopback redirect for Gemini CLI credentials)
# ---------------------------------------------------------------------------

GOOGLE_OAUTH_SCOPES = (
    "https://www.googleapis.com/auth/cloud-platform"
    " https://www.googleapis.com/auth/userinfo.email"
    " https://www.googleapis.com/auth/userinfo.profile"
)


def _google_callback_uri() -> str:
    """Build the loopback callback URI matching the running server."""
    return "http://127.0.0.1:8000/auth/google/callback"


@router.get("/google/login")
async def google_login_redirect() -> RedirectResponse:
    """Open this in a browser to start the Google OAuth flow."""
    params = urlencode({
        "client_id": settings.google_client_id,
        "redirect_uri": _google_callback_uri(),
        "response_type": "code",
        "scope": GOOGLE_OAUTH_SCOPES,
        "access_type": "offline",
        "prompt": "consent",
    })
    return RedirectResponse(f"https://accounts.google.com/o/oauth2/v2/auth?{params}")


@router.get("/google/callback", response_model=AuthResponse)
async def google_callback(
    code: str = Query(...),
    db: AsyncSession = Depends(get_db),
) -> AuthResponse:
    """Google OAuth callback — exchanges code for tokens and returns JWT."""
    try:
        user_info = await exchange_google_auth_code(code, _google_callback_uri())
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc

    google_sub = user_info["sub"]
    email = user_info.get("email")

    user = await _get_or_create_user_with_google(db, google_sub, email)

    refresh_token = user_info.get("refresh_token")
    if refresh_token:
        user.google_refresh_token = refresh_token
        await db.flush()

    return await _build_auth_response(db, user)
