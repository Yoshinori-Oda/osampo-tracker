"""tombstoneの長周期パージ(app/services/purge_service.py)のテスト。"""

from datetime import UTC, datetime, timedelta

from geoalchemy2 import WKTElement
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TrackingSession, TrackPoint, User
from app.services.purge_service import purge_expired_tombstones

RETENTION_DAYS = 90


async def add_session(
    db: AsyncSession, user: User, name: str, deleted_at: datetime | None
) -> TrackingSession:
    started_at = datetime(2026, 6, 1, 8, 0, tzinfo=UTC)
    tracking_session = TrackingSession(
        user_id=user.id,
        name=name,
        started_at=started_at,
        ended_at=started_at + timedelta(minutes=30),
        move_method="walk",
        deleted_at=deleted_at,
        track_points=[
            TrackPoint(
                location=WKTElement("POINTZ(139.767125 35.681236 10.5)", srid=4326),
                recorded_at=started_at,
            ),
        ],
    )
    db.add(tracking_session)
    await db.flush()
    return tracking_session


async def remaining_names(db: AsyncSession) -> set[str]:
    return set(await db.scalars(select(TrackingSession.name)))


async def test_purges_only_tombstones_older_than_retention(db_session: AsyncSession, user: User):
    now = datetime.now(UTC)
    expired = await add_session(
        db_session, user, "パージ期間を過ぎた削除", now - timedelta(days=RETENTION_DAYS + 1)
    )
    await add_session(
        db_session, user, "パージ期間内の削除", now - timedelta(days=RETENTION_DAYS - 1)
    )
    await add_session(db_session, user, "生きている", None)
    # 現行のfrontendが入れてくるパージ予定日時(未来の日時)は、新しい条件では消さない
    await add_session(db_session, user, "旧形式のtombstone", now + timedelta(days=30))

    purged = await purge_expired_tombstones(db_session, RETENTION_DAYS)

    assert purged == 1
    assert await remaining_names(db_session) == {"パージ期間内の削除", "生きている", "旧形式のtombstone"}
    # track_pointsもON DELETE CASCADEで一緒に消える
    remaining_points = await db_session.scalar(
        select(func.count()).where(TrackPoint.session_id == expired.id)
    )
    assert remaining_points == 0


async def test_purge_with_nothing_to_delete_returns_zero(db_session: AsyncSession, user: User):
    await add_session(db_session, user, "生きている", None)

    assert await purge_expired_tombstones(db_session, RETENTION_DAYS) == 0
