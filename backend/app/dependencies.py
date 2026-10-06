"""複数のエンドポイントで共通して使う依存関係(FastAPIのDepends用)。"""

from fastapi import Request

from app.errors import AppError, ErrorCode


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
