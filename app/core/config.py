"""設定の読み込み。値は .env から読む(コードに直接書かない)。"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # docker-compose.yml の設定(ポート5433)に合わせた、開発用の初期値
    database_url: str = "postgresql://covershift:covershift_dev@localhost:5433/covershift"

    # .env に書いてある、このクラスにない項目は無視する
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()