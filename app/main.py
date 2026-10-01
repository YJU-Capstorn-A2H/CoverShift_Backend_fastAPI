from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI

from app.core.db import close_pool, open_pool
from app.routers import health

load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    open_pool()   # 起動時: DBにつなぐ
    yield
    close_pool()  # 終了時: 接続を閉じる


app = FastAPI(lifespan=lifespan)
app.include_router(health.router)