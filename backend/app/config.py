from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


class Settings(BaseSettings):
    """環境変数(backend/.env)から読み込む設定。

    フィールド名は大文字小文字を区別せずに環境変数と対応する(例: postgres_db <- POSTGRES_DB)。
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # DB接続。ロール分離(マイグレーション用/アプリ用)までは、composeのdbと同じロールで接続する
    postgres_host: str = "db"
    postgres_port: int = 5432
    postgres_db: str
    postgres_user: str
    postgres_password: SecretStr

    # tombstoneのパージ(worker)。パージ期間はGETのrequest_existence_checkの判定でも参照する
    purge_retention_days: int = 90
    purge_interval_hours: int = 24

    @property
    def database_url(self) -> URL:
        return URL.create(
            "postgresql+psycopg",
            username=self.postgres_user,
            password=self.postgres_password.get_secret_value(),
            host=self.postgres_host,
            port=self.postgres_port,
            database=self.postgres_db,
        )


settings = Settings()
