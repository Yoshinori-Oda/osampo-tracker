"""削除済みのsession(tombstone)の長周期パージ。workerが定期実行する。

tombstoneは、他の端末が差分取得で削除を受け取れるよう、削除してからパージ期間(既定90日)は残しておく。
パージ期間を過ぎたものを物理削除する(track_pointsはsessionsのON DELETE CASCADEで一緒に消える)。
"""

from datetime import timedelta

from sqlalchemy import delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TrackingSession


async def purge_expired_tombstones(db: AsyncSession, retention_days: int) -> int:
    """deleted_at(削除した日時)がパージ期間より古いtombstoneを物理削除し、削除した件数を返す。"""
    result = await db.execute(
        delete(TrackingSession).where(
            TrackingSession.deleted_at.is_not(None),
            TrackingSession.deleted_at < func.clock_timestamp() - timedelta(days=retention_days),
        )
    )
    await db.commit()
    return result.rowcount
