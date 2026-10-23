"""リクエストの情報(送信元のIP)を、サービスの処理から参照できるようにする。

監査ログ(app/services/audit_service.py)に送信元を残すために使う。サービスの関数の引数で渡して回らずに済むよう、
ASGIのミドルウェアでcontextvarに入れる(リクエストごとに別の値になる)。
リバースプロキシを置いたら、X-Forwarded-For等をどこまで信用するかを決めて、取り方を見直す。
"""

import ipaddress
from contextvars import ContextVar

from starlette.types import ASGIApp, Receive, Scope, Send

_client_ip: ContextVar[str | None] = ContextVar("client_ip", default=None)


def client_ip() -> str | None:
    """今のリクエストの送信元のIP(リクエストの外・取れない場合はNone)。"""
    return _client_ip.get()


class RequestContextMiddleware:
    """リクエストの送信元のIPをcontextvarに入れるミドルウェア。"""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        token = _client_ip.set(_parse_ip(scope.get("client")))
        try:
            await self.app(scope, receive, send)
        finally:
            _client_ip.reset(token)


def _parse_ip(client: tuple[str, int] | None) -> str | None:
    # IPアドレスとして読めないもの(テスト用のクライアントの"testclient"等)は残さない(DBの型がINETのため)
    if client is None:
        return None
    try:
        return str(ipaddress.ip_address(client[0]))
    except ValueError:
        return None
