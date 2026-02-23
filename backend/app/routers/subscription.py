import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.subscription import Subscription, SubscriptionTier
from app.models.user import User
from app.schemas.subscription import SubscriptionResponse, VerifyReceiptRequest, VerifyReceiptResponse
from app.services.receipt_validator import validate_apple_receipt

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["subscription"])


@router.post("/verify-receipt", response_model=VerifyReceiptResponse)
async def verify_receipt(
    body: VerifyReceiptRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> VerifyReceiptResponse:
    try:
        validation_result = await validate_apple_receipt(
            receipt_data=body.receipt_data,
            product_id=body.product_id,
            transaction_id=body.transaction_id,
        )
    except ValueError as exc:
        logger.error("Receipt validation error for user %d: %s", current_user.id, exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc

    stmt = select(Subscription).where(Subscription.user_id == current_user.id)
    result = await db.execute(stmt)
    subscription = result.scalar_one_or_none()

    if subscription is None:
        subscription = Subscription(user_id=current_user.id)
        db.add(subscription)

    subscription.tier = validation_result["tier"]
    subscription.expires_at = validation_result["expires_at"]
    subscription.transaction_id = validation_result["transaction_id"]
    subscription.product_id = validation_result["product_id"]

    await db.flush()

    return VerifyReceiptResponse(
        success=True,
        new_tier=subscription.tier.value,
        expires_at=subscription.expires_at,
    )


@router.get("/subscription", response_model=SubscriptionResponse)
async def get_subscription(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SubscriptionResponse:
    stmt = select(Subscription).where(Subscription.user_id == current_user.id)
    result = await db.execute(stmt)
    subscription = result.scalar_one_or_none()

    if subscription is None:
        return SubscriptionResponse(tier=SubscriptionTier.FREE)

    return SubscriptionResponse(
        tier=subscription.tier,
        expires_at=subscription.expires_at,
        product_id=subscription.product_id,
    )
