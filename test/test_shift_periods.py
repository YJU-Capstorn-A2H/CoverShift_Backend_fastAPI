"""シフト期間API(管理者用)のテスト。実際のDBを使う。
テストで作る期間は、2031年に固定。テストの前後に、2031年の期間を全部消す。"""
import datetime as dt
import os
import uuid
import psycopg
import pytest
from dotenv import load_dotenv
from fastapi.testclient import TestClient
from app.main import app

# 環境変数を読み込む
load_dotenv()

# URL は、テストの中で何度も使うので、定数にしておく
URL = "/api/admin/shift-periods"


# テストの前後に、2031年の期間を全部消す
def _cleanup(db):
    ids = "SELECT period_id FROM shift_periods WHERE period_start >= '2031-01-01' AND period_start < '2032-01-01'"
    db.execute(f"DELETE FROM availability_submissions WHERE period_id IN ({ids})")
    db.execute("DELETE FROM shift_periods WHERE period_start >= '2031-01-01' AND period_start < '2032-01-01'")


# テストの前後で実行される処理を定義する。ここでは、DB接続を作って、テストの前後に 2031年の期間を消す
@pytest.fixture
def db():
    with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as conn:
        _cleanup(conn)
        yield conn
        _cleanup(conn)


# テストの前後で実行される処理を定義する。ここでは、TestClient を作って、テストの前後に 2031年の期間を消す
@pytest.fixture
def client(db):
    with TestClient(app) as c:
        yield c


# 「いまから days 日後の時刻(タイムゾーン付き)」を返す。今日の日付に左右されないようにする
def future(days):
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=days)).isoformat()


# 「新しい期間を作るときの、正しい入力の形」を返す。over で上書きできる
def body(**over):
    base = {
        "period_start": "2031-01-01",
        "period_end": "2031-01-31",
        "submission_deadline": future(10),
        "notify_at": future(1),
    }
    
    base.update(over)
    return base


# 期間を登録する。max_revision を省くと、初期値の2になる
def test_create_period(client):
    res = client.post(URL, json=body())
    assert res.status_code == 201
    out = res.json()
    assert out["period_start"] == "2031-01-01" and out["period_end"] == "2031-01-31"
    assert out["max_revision"] == 2
    assert out["notified_at"] is None  # まだ発送していない


# 作った期間は、希望提出APIで、そのまま使える(2つのAPIがつながる)
def test_created_period_accepts_availability(client, db):
    period_id = client.post(URL, json=body()).json()["period_id"]
    staff_id = db.execute(
        "INSERT INTO employees (name, employment_type) VALUES ('テスト用', 'arbeit') RETURNING staff_id"
    ).fetchone()[0]
    try:
        res = client.post(
            f"/api/staff/{staff_id}/availability",
            json={"period_id": period_id, "date": "2031-01-10", "start_time": "10:00", "end_time": "18:00"},
        )
        assert res.status_code == 201
    finally:
        db.execute("DELETE FROM availability_submissions WHERE staff_id = %s", (staff_id,))
        db.execute("DELETE FROM employees WHERE staff_id = %s", (staff_id,))


# 入力の形が、おかしいものは拒否される(422)
@pytest.mark.parametrize(
    "over",
    [
        {"period_end": "2030-12-31"},                       # 終了が開始より前
        {"submission_deadline": "2031-01-05T23:59:00"},     # タイムゾーンなし
        {"notify_at": "2031-01-01T09:00:00"},               # タイムゾーンなし
        {"max_revision": 0},                                # 1〜5の外
        {"max_revision": 6},                                # 1〜5の外
    ],
)
def test_invalid_input_is_rejected(client, over):
    assert client.post(URL, json=body(**over)).status_code == 422


# max_revision は、1と5まで許される(境目)
@pytest.mark.parametrize("n", [1, 5])
def test_max_revision_boundaries(client, n):
    res = client.post(URL, json=body(max_revision=n))
    assert res.status_code == 201 and res.json()["max_revision"] == n


# 発送予定が、締切より後だと、リンクが発行と同時に失効する。登録時に断る
def test_notify_after_deadline_is_rejected(client):
    res = client.post(URL, json=body(submission_deadline=future(1), notify_at=future(2)))
    assert res.status_code == 422
    assert res.json()["detail"]["code"] == "NOTIFY_AFTER_DEADLINE"


# 一覧は、開始日が新しい順
def test_list_is_newest_first(client):
    a = client.post(URL, json=body(period_start="2031-01-01", period_end="2031-01-31")).json()["period_id"]
    b = client.post(URL, json=body(period_start="2031-02-01", period_end="2031-02-28")).json()["period_id"]
    ids = [p["period_id"] for p in client.get(URL).json()]
    assert ids.index(b) < ids.index(a)


# 一部の項目だけ直せる。送らなかった項目は、そのまま
def test_patch_changes_only_given_fields(client):
    created = client.post(URL, json=body()).json()
    res = client.patch(f"{URL}/{created['period_id']}", json={"max_revision": 4})
    assert res.status_code == 200
    out = res.json()
    assert out["max_revision"] == 4
    assert out["submission_deadline"] == created["submission_deadline"]
    assert out["notify_at"] == created["notify_at"]


def test_patch_deadline(client):
    created = client.post(URL, json=body()).json()
    new_deadline = future(20)
    res = client.patch(f"{URL}/{created['period_id']}", json={"submission_deadline": new_deadline})
    assert res.status_code == 200
    got = dt.datetime.fromisoformat(res.json()["submission_deadline"])
    assert got == dt.datetime.fromisoformat(new_deadline)


# 何も送らない / 存在しないID
def test_patch_empty_body_is_rejected(client):
    created = client.post(URL, json=body()).json()
    res = client.patch(f"{URL}/{created['period_id']}", json={})
    assert res.status_code == 422 and res.json()["detail"]["code"] == "NO_FIELDS"


def test_patch_unknown_period(client):
    res = client.patch(f"{URL}/{uuid.uuid4()}", json={"max_revision": 3})
    assert res.status_code == 404 and res.json()["detail"]["code"] == "PERIOD_NOT_FOUND"


# 直したあとの値で、もう一度チェックする(締切を前倒しして、発送予定より前になるのは不可)
def test_patch_deadline_before_notify_is_rejected(client):
    created = client.post(URL, json=body(notify_at=future(5), submission_deadline=future(10))).json()
    res = client.patch(f"{URL}/{created['period_id']}", json={"submission_deadline": future(2)})
    assert res.status_code == 422 and res.json()["detail"]["code"] == "NOTIFY_AFTER_DEADLINE"


# 発送予定だけを直して、いまの締切より後にするのも不可(いまの値と合わせてチェックする)
def test_patch_notify_after_existing_deadline_is_rejected(client):
    created = client.post(URL, json=body(notify_at=future(1), submission_deadline=future(3))).json()
    res = client.patch(f"{URL}/{created['period_id']}", json={"notify_at": future(5)})
    assert res.status_code == 422 and res.json()["detail"]["code"] == "NOTIFY_AFTER_DEADLINE"


# すでに発送済みなら、発送予定日時は直せない(409)。ほかの項目は直せる
def test_patch_notify_at_after_sent_is_rejected(client, db):
    created = client.post(URL, json=body()).json()
    db.execute("UPDATE shift_periods SET notified_at = now() WHERE period_id = %s", (created["period_id"],))
    res = client.patch(f"{URL}/{created['period_id']}", json={"notify_at": future(2)})
    assert res.status_code == 409 and res.json()["detail"]["code"] == "NOTIFY_ALREADY_SENT"
    res = client.patch(f"{URL}/{created['period_id']}", json={"max_revision": 3})
    assert res.status_code == 200