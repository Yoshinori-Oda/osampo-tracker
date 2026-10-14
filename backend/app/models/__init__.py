"""テーブルの定義(SQLAlchemyのORM)。SpringのJPAの@Entityに相当する。

Alembicがmetadataから全てのテーブルを参照できるよう、モデルはここで全てimportする。
"""

from app.models.auth_session import AuthSession
from app.models.base import Base
from app.models.outbox_email import OutboxEmail
from app.models.refresh_token import RefreshToken
from app.models.track_point import TrackPoint
from app.models.tracking_session import TrackingSession
from app.models.user import User

__all__ = [
    "AuthSession",
    "Base",
    "OutboxEmail",
    "RefreshToken",
    "TrackPoint",
    "TrackingSession",
    "User",
]
