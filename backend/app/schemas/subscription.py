from datetime import datetime

from pydantic import BaseModel

from app.models.subscription import SubscriptionTier


class QuotaResponse(BaseModel):
    tier: SubscriptionTier
    requests_today: int
    daily_limit: int
    remaining: int
    resets_at: str


class SubscriptionResponse(BaseModel):
    tier: SubscriptionTier
    expires_at: datetime | None = None
    product_id: str | None = None


class VerifyReceiptResponse(BaseModel):
    success: bool
    new_tier: str | None = None
    expires_at: datetime | None = None


class VerifyReceiptRequest(BaseModel):
    receipt_data: str
    product_id: str
    transaction_id: str | None = None
