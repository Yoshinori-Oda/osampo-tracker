"""定期実行ジョブ(パージ・メール送信)を動かすworkerプロセス。

apiと同じイメージで、起動コマンドだけを`python -m app.worker`に変えて動かす。
ジョブが重複して実行されないよう、workerは1つだけ起動する。
"""

import asyncio
import logging
from datetime import UTC, datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.config import settings
from app.db import SessionLocal
from app.services.purge_service import purge_expired_tombstones

logger = logging.getLogger(__name__)


async def purge_job() -> None:
    """パージ期間を過ぎたtombstoneを物理削除する。失敗してもworkerは止めず、次の実行で再び試みる。"""
    try:
        async with SessionLocal() as db:
            purged = await purge_expired_tombstones(db, settings.purge_retention_days)
        logger.info("purged %d expired tombstone(s)", purged)
    except Exception:
        logger.exception("failed to purge expired tombstones")


async def main() -> None:
    logging.basicConfig(level=logging.INFO)

    scheduler = AsyncIOScheduler()
    scheduler.add_job(
        purge_job,
        "interval",
        hours=settings.purge_interval_hours,
        # 起動直後に1回実行し、以降はpurge_interval_hoursごとに実行する
        next_run_time=datetime.now(UTC),
        # 前回の実行が終わっていなければ重ねて実行しない。止まっていた間の実行分はまとめて1回にする
        max_instances=1,
        coalesce=True,
        id="purge_expired_tombstones",
    )
    scheduler.start()
    logger.info(
        "worker started (purge: every %d hour(s), retention %d day(s))",
        settings.purge_interval_hours,
        settings.purge_retention_days,
    )

    # スケジューラーはイベントループ上で動くので、プロセスを終了させずに待ち続ける
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
