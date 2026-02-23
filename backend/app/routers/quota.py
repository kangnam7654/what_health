import logging

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.subscription import QuotaResponse
from app.services.quota_service import get_quota_info

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["quota"])


@router.get("/quota", response_model=QuotaResponse)
async def get_quota(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> QuotaResponse:
    info = await get_quota_info(db, current_user.id)
    return QuotaResponse(**info)
