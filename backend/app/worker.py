"""定期実行ジョブ(パージ・メール送信)を動かすworkerプロセス。

apiと同じイメージで、起動コマンドだけを`python -m app.worker`に変えて動かす。
ジョブが重複して実行されないよう、workerは1つだけ起動する。
"""

import asyncio
import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler

logger = logging.getLogger(__name__)


async def main() -> None:
    logging.basicConfig(level=logging.INFO)

    scheduler = AsyncIOScheduler()
    # パージ処理(settings.purge_interval_hoursごと)は後続の作業で登録する
    scheduler.start()
    logger.info("worker started")

    # スケジューラーはイベントループ上で動くので、プロセスを終了させずに待ち続ける
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
