"""テーブルの定義(SQLAlchemyのORM)。SpringのJPAの@Entityに相当する。"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """全てのモデルの基底クラス。Alembicの自動生成はこのmetadataを参照する。"""
