from datetime import datetime, timezone

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    apple_user_id: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True, index=True)
    google_user_id: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True, index=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True, index=True)
    google_refresh_token: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    subscription: Mapped["Subscription"] = relationship(back_populates="user", uselist=False, lazy="selectin")  # type: ignore[name-defined]  # noqa: F821
    usage_records: Mapped[list["UsageRecord"]] = relationship(back_populates="user", lazy="selectin")  # type: ignore[name-defined]  # noqa: F821
