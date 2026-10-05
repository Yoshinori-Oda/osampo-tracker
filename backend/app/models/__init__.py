"""テーブルの定義(SQLAlchemyのORM)。SpringのJPAの@Entityに相当する。

Alembicがmetadataから全てのテーブルを参照できるよう、モデルはここで全てimportする。
"""

from app.models.base import Base
from app.models.track_point import TrackPoint
from app.models.tracking_session import TrackingSession
from app.models.user import User

__all__ = ["Base", "TrackPoint", "TrackingSession", "User"]
