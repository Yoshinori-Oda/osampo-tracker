from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings

engine = create_async_engine(settings.app_database_url, pool_pre_ping=True)

# commit後に属性へアクセスしても再読み込み(=暗黙のDBアクセス)が起きないようにする。
# 非同期では暗黙のDBアクセスがエラーになるため
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """リクエストごとにDBセッションを渡す依存関係(FastAPIのDepends用)。"""
    async with SessionLocal() as session:
        yield session
