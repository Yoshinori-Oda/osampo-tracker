"""同期API(/api/users/{user_id}/sessions)。仕様はbackend/docs/API設計ドラフト.mdを参照。

ここではHTTPの受け口(パス・メソッド・ステータスコード・依存関係)だけを扱い、業務ルールはservices層に任せる。
"""

import uuid

from fastapi import APIRouter, Depends, Response, status
from pydantic import AwareDatetime

from app.config import settings
from app.dependencies import (
    DbSession,
    TargetUserId,
    require_json_accept,
    require_json_content_type,
)
from app.schemas.error import ErrorResponse
from app.schemas.session import (
    ExistenceCheckRequest,
    ExistenceCheckResponse,
    SessionCreate,
    SessionEdit,
    SyncResponse,
    UpdatedAtResponse,
)
from app.services import session_service

# 全てのエンドポイントで起こりうるエラー(OpenAPIのドキュメント用)
router = APIRouter(
    prefix="/api/users/{user_id}/sessions",
    tags=["sessions"],
    responses={
        404: {"model": ErrorResponse, "description": "user_not_found / session_not_found"},
        422: {"model": ErrorResponse, "description": "validation_error"},
    },
)

# bodyを受け取るエンドポイントで起こりうるエラー
BODY_ERRORS = {
    413: {"model": ErrorResponse, "description": "payload_too_large"},
    415: {"model": ErrorResponse, "description": "unsupported_media_type"},
}


@router.get(
    "",
    response_model=SyncResponse,
    dependencies=[Depends(require_json_accept)],
    responses={406: {"model": ErrorResponse, "description": "not_acceptable"}},
)
async def fetch_sessions(
    user_id: TargetUserId,
    db: DbSession,
    last_synced_at: AwareDatetime | None = None,
) -> SyncResponse:
    """差分取得。last_synced_atを省略すると初回の同期として、削除済みを除く全てのsessionを返す。"""
    return await session_service.fetch_sessions(
        db, user_id, last_synced_at, settings.purge_retention_days
    )


@router.post(
    "",
    response_model=UpdatedAtResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_json_content_type)],
    responses={
        200: {"model": UpdatedAtResponse, "description": "同じidの再送(登録済み)"},
        409: {"model": ErrorResponse, "description": "id_conflicted / deleted"},
        **BODY_ERRORS,
    },
)
async def register_session(
    user_id: TargetUserId,
    body: SessionCreate,
    db: DbSession,
    response: Response,
) -> UpdatedAtResponse:
    """登録。新規なら201、同じidの再送なら200を返す。"""
    status_code, updated_at = await session_service.register_session(db, user_id, body)
    response.status_code = status_code
    return UpdatedAtResponse(updated_at=updated_at)


# "/existence-check"は"/{session_id}"より先に定義する(パスの照合は定義順に行われるため)
@router.post(
    "/existence-check",
    response_model=ExistenceCheckResponse,
    dependencies=[Depends(require_json_content_type)],
    responses=BODY_ERRORS,
)
async def check_existence(
    user_id: TargetUserId,
    body: ExistenceCheckRequest,
    db: DbSession,
) -> ExistenceCheckResponse:
    """削除の突き合わせ。当該ユーザーの生きているsessionとして存在しないIDを返す。"""
    missing = await session_service.find_missing_session_ids(db, user_id, body.session_ids)
    return ExistenceCheckResponse(missing_session_ids=missing)


@router.patch(
    "/{session_id}",
    response_model=UpdatedAtResponse,
    dependencies=[Depends(require_json_content_type)],
    responses={409: {"model": ErrorResponse, "description": "deleted"}, **BODY_ERRORS},
)
async def edit_session(
    user_id: TargetUserId,
    session_id: uuid.UUID,
    body: SessionEdit,
    db: DbSession,
) -> UpdatedAtResponse:
    """修正。削除済みなら409(deleted)、パージ済み・他ユーザーのものなら404(session_not_found)。"""
    updated_at = await session_service.edit_session(db, user_id, session_id, body, restore=False)
    return UpdatedAtResponse(updated_at=updated_at)


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(
    user_id: TargetUserId,
    session_id: uuid.UUID,
    db: DbSession,
) -> Response:
    """削除(tombstoneにする)。既に削除済みでも204。"""
    await session_service.delete_session(db, user_id, session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{session_id}/restore",
    response_model=UpdatedAtResponse,
    dependencies=[Depends(require_json_content_type)],
    responses=BODY_ERRORS,
)
async def restore_session(
    user_id: TargetUserId,
    session_id: uuid.UUID,
    body: SessionEdit,
    db: DbSession,
) -> UpdatedAtResponse:
    """削除の取り消し。可変の項目も同時に反映する。パージ済みなら404(session_not_found)。"""
    updated_at = await session_service.edit_session(db, user_id, session_id, body, restore=True)
    return UpdatedAtResponse(updated_at=updated_at)
