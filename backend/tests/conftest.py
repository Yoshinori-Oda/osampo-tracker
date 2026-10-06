import os

# pytestは常にテスト用のデータベース(POSTGRES_TEST_DB)に接続する。
# app.configのSettingsはimport時に環境変数を読むので、appをimportする前に書き換える
os.environ["POSTGRES_DB"] = os.environ.get("POSTGRES_TEST_DB", "location_db_test")

import uuid  # noqa: E402
from collections.abc import AsyncIterator  # noqa: E402

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine  # noqa: E402
from sqlalchemy.pool import NullPool  # noqa: E402

from app.config import settings  # noqa: E402
from app.db import DB_CONNECT_ARGS, get_session  # noqa: E402
from app.main import app  # noqa: E402
from app.models import User  # noqa: E402


@pytest.fixture
async def db_session() -> AsyncIterator[AsyncSession]:
    """テストごとにトランザクションを開始し、最後にロールバックするDBセッション(データはテスト用DBに残らない)。

    APIの処理の中でのcommit()は、join_transaction_mode="create_savepoint"によってセーブポイントの確定になり、
    外側のトランザクションは確定しない。
    """
    # テストごとにイベントループが変わるので、接続を使い回さない(NullPool)
    engine = create_async_engine(
        settings.app_database_url, poolclass=NullPool, connect_args=DB_CONNECT_ARGS
    )
    async with engine.connect() as connection:
        transaction = await connection.begin()
        session = AsyncSession(
            bind=connection,
            join_transaction_mode="create_savepoint",
            expire_on_commit=False,
        )
        try:
            yield session
        finally:
            await session.close()
            await transaction.rollback()
    await engine.dispose()


@pytest.fixture
async def api_client(db_session: AsyncSession) -> AsyncIterator[AsyncClient]:
    """APIを呼ぶクライアント。APIのDBセッションをdb_sessionに差し替える(FastAPIのdependency_overrides)。"""

    async def override_get_session() -> AsyncIterator[AsyncSession]:
        yield db_session

    app.dependency_overrides[get_session] = override_get_session
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            yield client
    finally:
        app.dependency_overrides.clear()


async def create_user(db_session: AsyncSession) -> User:
    user = User(email=f"{uuid.uuid4()}@example.com")
    db_session.add(user)
    await db_session.flush()
    return user


@pytest.fixture
async def user(db_session: AsyncSession) -> User:
    return await create_user(db_session)


@pytest.fixture
async def other_user(db_session: AsyncSession) -> User:
    return await create_user(db_session)
