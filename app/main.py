# このアプリには、どんなAPIがあって、起動と終了のときに何をするかを、まとめて決める
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from fastapi import FastAPI
from app.core.db import close_pool, open_pool
from app.routers import availability, health

# 環境変数を読み込む
load_dotenv()

# アプリケーションのライフサイクルを管理する
@asynccontextmanager
# アプリケーションが起動するときと終了するときに実行される処理を定義する
async def lifespan(app: FastAPI):
    open_pool()   # 起動時: DBにつなぐ
    yield
    close_pool()  # 終了時: 接続を閉じる


# アプリケーションのインスタンスを作成する
app = FastAPI(lifespan=lifespan)
app.include_router(health.router)
app.include_router(availability.router)