"""自分のアカウント(/api/users/me)。仕様はbackend/docs/API設計ドラフト.mdの「認証のendpoints」。

将来、管理者向けに他ユーザーを操作する機能を作るときは、/api/users/{user_id} のendpointを別に追加する。
"""

from fastapi import APIRouter, Depends, Response, status

from app.dependencies import CurrentAuth, DbSession, require_json_content_type
from app.errors import ErrorCode
from app.schemas.auth import UpdateMeRequest, UserResponse
from app.schemas.error import error_responses
from app.services import auth_service

router = APIRouter(prefix="/api/users/me", tags=["users"])

_AUTH = {401: [ErrorCode.UNAUTHENTICATED, ErrorCode.TOKEN_EXPIRED]}


@router.get(
    "",
    summary="自分の情報",
    response_model=UserResponse,
    responses=error_responses(_AUTH),
)
async def get_me(auth: CurrentAuth) -> UserResponse:
    return auth_service.user_response(auth.user)


@router.patch(
    "",
    summary="自分の情報の変更",
    response_model=UserResponse,
    dependencies=[Depends(require_json_content_type)],
    responses=error_responses(
        {
            **_AUTH,
            413: [ErrorCode.PAYLOAD_TOO_LARGE],
            415: [ErrorCode.UNSUPPORTED_MEDIA_TYPE],
            422: [ErrorCode.VALIDATION_ERROR],
        }
    ),
)
async def update_me(body: UpdateMeRequest, auth: CurrentAuth, db: DbSession) -> UserResponse:
    """表示名を変更する(メールアドレス・パスワードの変更は別のendpoint)。"""
    return await auth_service.update_me(db, auth.user, body)


@router.delete(
    "",
    summary="アカウントの削除",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=error_responses(_AUTH),
)
async def delete_me(auth: CurrentAuth, db: DbSession) -> Response:
    """アカウントを物理削除する(セッション・トラックポイント・端末のログイン状態も一緒に消える)。

    アプリの審査で求められる「アプリ内からのアカウントと関連データの削除」に当たる。他の端末は次のリクエストで401になる。
    """
    await auth_service.delete_me(db, auth.user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
