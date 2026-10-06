from fastapi import FastAPI

from app.config import settings
from app.error_handlers import install_error_handling
from app.routers import health

app = FastAPI(title="osampo-tracker API")

# エラーを共通の形式({"code", "message", "details"})で返す例外ハンドラーと、bodyのサイズの上限
install_error_handling(app, max_body_bytes=settings.max_request_body_bytes)

# /healthは運用(composeのhealthcheck)用なので、APIのパス(/api/...)の外に置く
app.include_router(health.router)
