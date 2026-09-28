import os
import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()
app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/health/db")
def health_db():
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
        row = conn.execute("SELECT 1").fetchone()
    return {"db": "ok", "result": row[0]}