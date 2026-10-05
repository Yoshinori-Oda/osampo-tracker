from fastapi import FastAPI

from app.routers import health

app = FastAPI(title="osampo-tracker API")

# /healthは運用(composeのhealthcheck)用なので、APIのパス(/api/...)の外に置く
app.include_router(health.router)
