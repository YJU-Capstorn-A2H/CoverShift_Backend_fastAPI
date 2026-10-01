"""希望提出の業務ルール。SQLは書かず repositories を呼ぶ。"""
import datetime as dt
from uuid import UUID
import psycopg
from app.repositories import availability_repository as repo
from app.schemas.availability import AvailabilityIn
from app.services.errors import ForbiddenError, InvalidInputError, NotFoundError


# _load_staff_and_period：従業員とシフト期間を読み込む
def _load_staff_and_period(conn: psycopg.Connection, staff_id: UUID, period_id: UUID) -> dict:
    staff = repo.get_staff(conn, staff_id)
    # 退職などで is_active=false の人も「いない」扱いにする(案)
    if staff is None or not staff["is_active"]:
        raise NotFoundError("STAFF_NOT_FOUND", "従業員が見つかりません")
    period = repo.get_period(conn, period_id)
    # 従業員も期間も、見つからなければ HTTP 404 になる(errors.py の NotFoundError)
    if period is None:
        raise NotFoundError("PERIOD_NOT_FOUND", "シフト期間が見つかりません")
    return period


# submit：希望提出を登録する
def submit(conn: psycopg.Connection, staff_id: UUID, data: AvailabilityIn) -> dict:
    period = _load_staff_and_period(conn, staff_id, data.period_id)

    # 締切後は受け付けない(マジックリンクも締切で失効する設計。締切後の変更は店長が画面で直接直す)
    if dt.datetime.now(dt.timezone.utc) > period["submission_deadline"]:
        raise ForbiddenError("SUBMISSION_CLOSED", "提出の締切を過ぎています。変更は店長に連絡してください")

    # 提出日が期間内かどうかをチェック
    if not (period["period_start"] <= data.date <= period["period_end"]):
        raise InvalidInputError("DATE_OUT_OF_PERIOD", "日付が、対象期間の外です")

    # 同じ人・同じ期間・同じ日の「最新の提出」を探す(置き換えられていないもの)
    previous = repo.find_current_for_update(conn, staff_id, data.period_id, data.date)
    row = repo.insert_submission(
        conn, staff_id, data.period_id, data.date, data.start_time, data.end_time
    )

    # 古い提出に「この新しい提出に置き換えられた」と印をつける(履歴は消さない)
    if previous is not None:
        repo.mark_superseded(conn, previous["id"], row["id"])

    return {
        **row,
        # 締切後は上で断っているので、ここは通常 False(締切を後から前倒しした場合のために残す)
        "is_late": row["submitted_at"] > period["submission_deadline"],
        "replaced_previous": previous is not None,
    }


# get_status：希望提出の状況を取得する
def get_status(conn: psycopg.Connection, staff_id: UUID, period_id: UUID) -> dict:
    # 従業員とシフト期間を読み込む
    period = _load_staff_and_period(conn, staff_id, period_id)
    rows = repo.list_current(conn, staff_id, period_id)
    deadline = period["submission_deadline"]
    items = [{**r, "is_late": r["submitted_at"] > deadline} for r in rows]

    return {
        "period_id": period_id,
        "submission_deadline": deadline,
        "total_days": (period["period_end"] - period["period_start"]).days + 1,
        "submitted_days": len(items),
        "items": items,
    }