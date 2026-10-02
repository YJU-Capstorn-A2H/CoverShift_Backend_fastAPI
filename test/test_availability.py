"""希望提出APIのテスト。実際のDBを使う(テスト用の従業員・期間を作って、終わったら消す)。"""
import os
import uuid
import psycopg
import pytest
from dotenv import load_dotenv
from fastapi.testclient import TestClient
from app.main import app

# .env を読む
load_dotenv()

# テスト用のDB接続。autocommit=True にして、テストデータを作ったらすぐ確定する
@pytest.fixture
# テストデータを生成する
def data():
    """使い捨てのテストデータ: 従業員1人 + 受付中の期間 + 締切済みの期間"""
    with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as db:
        staff_id = db.execute(
            "INSERT INTO employees (name, employment_type) " \
            "VALUES ('テスト用', 'arbeit') " \
            "RETURNING staff_id"
        ).fetchone()[0]

        # 日付は遠い未来(2030年)に固定。締切だけ「いま」からの相対にして、今日の日付に左右されないようにする
        open_period = db.execute(
            "INSERT INTO shift_periods (period_start, period_end, submission_deadline, notify_at) "
            "VALUES ('2030-01-01', '2030-01-31', now() + interval '1 day', now()) " \
            "RETURNING period_id"
        ).fetchone()[0]

        # 締切済みの期間も作る。締切が過ぎているので、希望提出は拒否される(403)
        closed_period = db.execute(
            "INSERT INTO shift_periods (period_start, period_end, submission_deadline, notify_at) "
            "VALUES ('2030-02-01', '2030-02-28', now() - interval '1 day', now() - interval '2 days') " \
            "RETURNING period_id"
        ).fetchone()[0]

        # テストデータを yield で返す。テストが終わったら finally で削除する
        try:
            yield {"staff_id": staff_id, "open": open_period, "closed": closed_period, "db": db}
        finally:
            db.execute("DELETE FROM availability_submissions WHERE staff_id = %s", (staff_id,))
            db.execute("DELETE FROM shift_periods WHERE period_id IN (%s, %s)", (open_period, closed_period))
            db.execute("DELETE FROM employees WHERE staff_id = %s", (staff_id,))


# TestClient を使うと、FastAPI の起動処理(lifespan)も動く
@pytest.fixture
def client():
    with TestClient(app) as c:  # with を使うと、起動処理(lifespan)も動く
        yield c


# POST /api/staff/{staff_id}/availability のヘルパー
def post(client, staff_id, period_id, day, start=None, end=None):
    return client.post(
        f"/api/staff/{staff_id}/availability",
        json={"period_id": str(period_id), "date": day, "start_time": start, "end_time": end},
    )


# 通常の勤務日を提出する
def test_submit_work_day_on_time(client, data):
    res = post(client, data["staff_id"], data["open"], "2030-01-10", "10:00", "18:00")
    assert res.status_code == 201
    body = res.json()
    assert body["is_late"] is False
    assert body["replaced_previous"] is False
    assert body["start_time"] == "10:00:00" and body["end_time"] == "18:00:00"


# 休日を提出する
def test_submit_day_off(client, data):
    res = post(client, data["staff_id"], data["open"], "2030-01-11")  # 開始・終了なし = 休み希望
    assert res.status_code == 201
    assert res.json()["start_time"] is None and res.json()["end_time"] is None


# 締切後の提出は拒否される(403)。何も保存されない
def test_submission_after_deadline_is_rejected(client, data):
    res = post(client, data["staff_id"], data["closed"], "2030-02-10", "10:00", "14:00")
    assert res.status_code == 403
    assert res.json()["detail"]["code"] == "SUBMISSION_CLOSED"

    # 拒否されたので、何も保存されていない
    res = client.get(f"/api/staff/{data['staff_id']}/availability", params={"period_id": str(data["closed"])})
    assert res.status_code == 200  # 状況の確認(GET)は、締切後でもできる
    assert res.json()["submitted_days"] == 0


# 同じ日付に2回提出すると、古い提出は「置き換えられた」として残る
def test_resubmit_replaces_previous_and_keeps_history(client, data):
    first = post(client, data["staff_id"], data["open"], "2030-01-12", "10:00", "14:00").json()
    second = post(client, data["staff_id"], data["open"], "2030-01-12", "14:00", "22:00").json()
    assert second["replaced_previous"] is True

    # 古い提出には「置き換えた提出のID」が入り、行は消えない
    old = data["db"].execute(
        "SELECT superseded_by FROM availability_submissions WHERE id = %s", (first["id"],)
    ).fetchone()
    assert str(old[0]) == second["id"]

    # 一覧には、最新の1件だけが出る
    res = client.get(f"/api/staff/{data['staff_id']}/availability", params={"period_id": str(data["open"])})
    items = res.json()["items"]
    assert len(items) == 1 and items[0]["id"] == second["id"]


# 提出状況の一覧を取得する。提出済みの日数と、合計日数が返る
def test_status_shows_progress(client, data):
    post(client, data["staff_id"], data["open"], "2030-01-01", "10:00", "18:00")
    post(client, data["staff_id"], data["open"], "2030-01-02")
    res = client.get(f"/api/staff/{data['staff_id']}/availability", params={"period_id": str(data["open"])})
    assert res.status_code == 200
    body = res.json()
    assert body["total_days"] == 31 and body["submitted_days"] == 2
    assert [i["date"] for i in body["items"]] == ["2030-01-01", "2030-01-02"]


# 不正な時刻の組み合わせは拒否される
@pytest.mark.parametrize(
    "start,end",
    [
        ("10:00", None),      # 片方だけ
        (None, "18:00"),      # 片方だけ
        ("18:00", "10:00"),   # 終了が開始より前
        ("10:00", "10:00"),   # 同じ時刻
    ],
)

# パラメータ化されたテスト。start と end の組み合わせを変えて、422 が返ることを確認する
def test_invalid_times_are_rejected(client, data, start, end):
    res = post(client, data["staff_id"], data["open"], "2030-01-15", start, end)
    assert res.status_code == 422


# 期間外の日付は拒否される
def test_date_outside_period_is_rejected(client, data):
    res = post(client, data["staff_id"], data["open"], "2030-03-01", "10:00", "18:00")
    assert res.status_code == 422
    assert res.json()["detail"]["code"] == "DATE_OUT_OF_PERIOD"


# 存在しない従業員ID・期間IDは404になる
def test_unknown_staff_and_period(client, data):
    res = post(client, uuid.uuid4(), data["open"], "2030-01-10", "10:00", "18:00")
    assert res.status_code == 404 and res.json()["detail"]["code"] == "STAFF_NOT_FOUND"
    res = post(client, data["staff_id"], uuid.uuid4(), "2030-01-10", "10:00", "18:00")
    assert res.status_code == 404 and res.json()["detail"]["code"] == "PERIOD_NOT_FOUND"


# 非アクティブの従業員は404になる
def test_inactive_staff_is_treated_as_not_found(client, data):
    data["db"].execute("UPDATE employees SET is_active = false WHERE staff_id = %s", (data["staff_id"],))
    res = post(client, data["staff_id"], data["open"], "2030-01-10", "10:00", "18:00")
    assert res.status_code == 404