from fastapi import FastAPI
from fastapi.routing import APIRoute

from app.config import settings
from app.error_handlers import install_error_handling
from app.routers import auth, health, sessions, users

DESCRIPTION = """
osampo-trackerの同期API。OpenAPIは実装から自動生成している。判断の理由・処理の手順は
`backend/docs/API設計ドラフト.md`を参照(役割分担: 設計書=理由と手順、OpenAPI=入出力の型と例)。

- エラーは全て `{"code": ..., "message": ..., "details": [...]}` の形式で返す。クライアントは`code`で処理を分岐する
  (`details`は422のときだけ含める)
- 時刻は全てUTC(ISO 8601、"Z"付き)。リクエストの日時もタイムゾーン付きのみ受け付ける
- 認証: `POST /api/auth/login`等で取得したアクセストークンを`Authorization: Bearer`で送る(この画面では右上の「Authorize」で設定できる)。
  アクセストークンの有効期限が切れたら401(`token_expired`)になるので、`POST /api/auth/refresh`で更新する
- 同期API(`/api/users/{user_id}/sessions`)は、メールアドレスの確認が済んだユーザーだけが使える
"""


def _operation_id(route: APIRoute) -> str:
    """operationIdを関数名にする(既定はパスとメソッドを連結した長い名前になるため)。"""
    return route.name


app = FastAPI(
    title="osampo-tracker API",
    version="0.1.0",
    description=DESCRIPTION,
    generate_unique_id_function=_operation_id,
)

# エラーを共通の形式({"code", "message", "details"})で返す例外ハンドラーと、bodyのサイズの上限
install_error_handling(app, max_body_bytes=settings.max_request_body_bytes)

# /healthは運用(composeのhealthcheck)用なので、APIのパス(/api/...)の外に置く
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(sessions.router)
