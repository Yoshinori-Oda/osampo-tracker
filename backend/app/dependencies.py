"""複数のエンドポイントで共通して使う依存関係(FastAPIのDepends用)。"""

import uuid
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.errors import AppError, ErrorCode
from app.services import session_service

DbSession = Annotated[AsyncSession, Depends(get_session)]


async def require_json_content_type(request: Request) -> None:
    """bodyを受け取るエンドポイント(POST・PATCH)で、Content-Typeがapplication/jsonであることを確認する。

    依存関係はbodyの入力チェックより先に実行されるので、JSON以外のbodyは422ではなく415になる。
    """
    content_type = request.headers.get("content-type", "")
    # "application/json; charset=utf-8"のようなパラメーター付きも受け付ける
    if content_type.split(";")[0].strip().lower() != "application/json":
        raise AppError(
            415,
            ErrorCode.UNSUPPORTED_MEDIA_TYPE,
            "Content-Typeはapplication/jsonにしてください",
        )


async def require_json_accept(request: Request) -> None:
    """Acceptでapplication/jsonを受け付けていなければ406にする(Acceptが無ければ何でも受け付けるとみなす)。"""
    accept = request.headers.get("accept")
    if accept is None:
        return
    media_ranges = {part.split(";")[0].strip().lower() for part in accept.split(",")}
    if media_ranges.isdisjoint({"application/json", "application/*", "*/*"}):
        raise AppError(406, ErrorCode.NOT_ACCEPTABLE, "レスポンスはapplication/jsonでのみ返せます")


async def verify_user_access(user_id: uuid.UUID, db: DbSession) -> uuid.UUID:
    """パスパラメーターのuser_idのユーザーを操作してよいかを確認し、user_idを返す。

    認証(ブロック2)を実装するまではトークンを検証せず、user_idのユーザーが存在するかだけを確認する。
    認証の実装後は、API設計書の「認証と権限」の順(401→403→404)で判定する。
    """
    # TODO(ブロック2): トークンの検証(401)と、管理者でなく自分以外のuser_idを指定した場合の403
    await session_service.ensure_user_exists(db, user_id)
    return user_id


TargetUserId = Annotated[uuid.UUID, Depends(verify_user_access)]
