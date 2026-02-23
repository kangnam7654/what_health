import logging
from datetime import date, datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.subscription import Subscription, SubscriptionTier
from app.models.usage import UsageRecord

logger = logging.getLogger(__name__)

DAILY_LIMITS: dict[SubscriptionTier, int] = {
    SubscriptionTier.FREE: 10,
    SubscriptionTier.BASIC: 100,
    SubscriptionTier.PREMIUM: 1000,
}


def _get_daily_limit(tier: SubscriptionTier) -> int:
    return DAILY_LIMITS.get(tier, DAILY_LIMITS[SubscriptionTier.FREE])


async def _get_or_create_usage(db: AsyncSession, user_id: int, today: date) -> UsageRecord:
    stmt = select(UsageRecord).where(
        UsageRecord.user_id == user_id,
        UsageRecord.date == today,
    )
    result = await db.execute(stmt)
    record = result.scalar_one_or_none()

    if record is None:
        record = UsageRecord(user_id=user_id, date=today, request_count=0)
        db.add(record)
        await db.flush()

    return record


async def _get_user_tier(db: AsyncSession, user_id: int) -> SubscriptionTier:
    stmt = select(Subscription).where(Subscription.user_id == user_id)
    result = await db.execute(stmt)
    subscription = result.scalar_one_or_none()

    if subscription is None:
        return SubscriptionTier.FREE

    if subscription.expires_at and subscription.expires_at < datetime.now(timezone.utc):
        return SubscriptionTier.FREE

    return subscription.tier


async def check_quota(db: AsyncSession, user_id: int) -> tuple[bool, int, int, int]:
    """
    Returns (has_quota, requests_today, daily_limit, remaining).
    """
    today = date.today()
    tier = await _get_user_tier(db, user_id)
    daily_limit = _get_daily_limit(tier)
    record = await _get_or_create_usage(db, user_id, today)

    remaining = max(0, daily_limit - record.request_count)
    has_quota = record.request_count < daily_limit

    return has_quota, record.request_count, daily_limit, remaining


async def decrement_quota(db: AsyncSession, user_id: int) -> bool:
    """
    Decrement quota by 1. Returns False if quota already exhausted.
    """
    today = date.today()
    tier = await _get_user_tier(db, user_id)
    daily_limit = _get_daily_limit(tier)
    record = await _get_or_create_usage(db, user_id, today)

    if record.request_count >= daily_limit:
        return False

    record.request_count += 1
    await db.flush()
    return True


async def get_quota_info(db: AsyncSession, user_id: int) -> dict:
    today = date.today()
    tier = await _get_user_tier(db, user_id)
    daily_limit = _get_daily_limit(tier)
    record = await _get_or_create_usage(db, user_id, today)

    tomorrow = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
    from datetime import timedelta
    tomorrow = tomorrow + timedelta(days=1)

    return {
        "tier": tier,
        "requests_today": record.request_count,
        "daily_limit": daily_limit,
        "remaining": max(0, daily_limit - record.request_count),
        "resets_at": tomorrow.isoformat(),
    }
