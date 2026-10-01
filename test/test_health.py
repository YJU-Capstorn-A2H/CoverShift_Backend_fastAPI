from fastapi.testclient import TestClient

from app.main import app


def test_health():
    with TestClient(app) as client:  # with を使うと、起動処理(lifespan)も動く
        res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_health_db():
    with TestClient(app) as client:
        res = client.get("/health/db")
    assert res.status_code == 200
    assert res.json() == {"db": "ok", "result": 1}