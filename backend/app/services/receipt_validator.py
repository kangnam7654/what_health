import logging
from datetime import datetime, timezone
from typing import Any

import httpx

from app.config import settings
from app.models.subscription import SubscriptionTier

logger = logging.getLogger(__name__)

APP_STORE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt"
APP_STORE_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt"

PRODUCT_TIER_MAP: dict[str, SubscriptionTier] = {
    "com.exerciseplan.app.basic.monthly": SubscriptionTier.BASIC,
    "com.exerciseplan.app.basic.yearly": SubscriptionTier.BASIC,
    "com.exerciseplan.app.premium.monthly": SubscriptionTier.PREMIUM,
    "com.exerciseplan.app.premium.yearly": SubscriptionTier.PREMIUM,
}


def _product_id_to_tier(product_id: str) -> SubscriptionTier:
    for key, tier in PRODUCT_TIER_MAP.items():
        if product_id.startswith(key) or product_id == key:
            return tier
    if "premium" in product_id.lower():
        return SubscriptionTier.PREMIUM
    if "basic" in product_id.lower():
        return SubscriptionTier.BASIC
    return SubscriptionTier.FREE


async def _verify_with_apple(receipt_data: str, url: str) -> dict[str, Any]:
    payload = {
        "receipt-data": receipt_data,
        "password": "",  # shared secret for auto-renewable subscriptions
        "exclude-old-transactions": True,
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, json=payload)
        response.raise_for_status()
        return response.json()


async def validate_apple_receipt(
    receipt_data: str,
    product_id: str,
    transaction_id: str | None = None,
) -> dict[str, Any]:
    """
    Validate Apple IAP receipt. Returns tier, expires_at, and transaction_id.
    Uses sandbox fallback per Apple's recommended flow.
    """
    try:
        result = await _verify_with_apple(receipt_data, APP_STORE_PRODUCTION_URL)
        status = result.get("status", -1)

        if status == 21007:
            logger.info("Production receipt is from sandbox, retrying with sandbox URL")
            result = await _verify_with_apple(receipt_data, APP_STORE_SANDBOX_URL)
            status = result.get("status", -1)

        if status != 0:
            raise ValueError(f"Apple receipt validation failed with status: {status}")

        latest_receipts = result.get("latest_receipt_info", [])
        if not latest_receipts:
            in_app = result.get("receipt", {}).get("in_app", [])
            if not in_app:
                raise ValueError("No receipt info found in Apple response")
            latest_receipts = in_app

        matching = [r for r in latest_receipts if r.get("product_id") == product_id]
        receipt_info = matching[-1] if matching else latest_receipts[-1]

        expires_ms = receipt_info.get("expires_date_ms")
        expires_at: datetime | None = None
        if expires_ms:
            expires_at = datetime.fromtimestamp(int(expires_ms) / 1000, tz=timezone.utc)

        found_transaction_id = receipt_info.get("transaction_id", transaction_id)
        found_product_id = receipt_info.get("product_id", product_id)
        tier = _product_id_to_tier(found_product_id)

        return {
            "tier": tier,
            "expires_at": expires_at,
            "transaction_id": found_transaction_id,
            "product_id": found_product_id,
        }

    except httpx.HTTPError as exc:
        logger.error("HTTP error during Apple receipt validation: %s", exc)
        raise ValueError(f"Failed to contact Apple servers: {exc}") from exc
