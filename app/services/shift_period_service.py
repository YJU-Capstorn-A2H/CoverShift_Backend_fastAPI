"""シフト期間の業務ルール。SQLは書かず repositories を呼ぶ。"""
from uuid import UUID
import psycopg
from app.repositories import shift_period_repository as repo
from app.schemas.shift_period import ShiftPeriodCreate, ShiftPeriodPatch
from app.services.errors import ConflictError, InvalidInputError, NotFoundError


# 「締切より後に発送予定日時を設定しようとしていないか」をチェックする
def _check_notify_before_deadline(notify_at, deadline) -> None:
    # マジックリンクの有効期限は「締切」まで。発送が締切より後だと、発行した瞬間に失効する(案)
    if notify_at > deadline:
        raise InvalidInputError(
            "NOTIFY_AFTER_DEADLINE", "発送予定日時(notify_at)が、提出の締切より後になっています"
        )


# 「新しい期間を作る」(SQLは repositories の insert_period)
def create(conn: psycopg.Connection, data: ShiftPeriodCreate) -> dict:
    _check_notify_before_deadline(data.notify_at, data.submission_deadline)
    return repo.insert_period(conn, data.model_dump())


# 「期間の一覧を返す」(SQLは repositories の list_periods)
def list_all(conn: psycopg.Connection) -> list[dict]:
    return repo.list_periods(conn)


# 「期間を更新する」(SQLは repositories の update_period)
def update(conn: psycopg.Connection, period_id: UUID, data: ShiftPeriodPatch) -> dict:
    changes = data.model_dump(exclude_unset=True)  # 送られてきた項目だけ
    changes = {k: v for k, v in changes.items() if v is not None}
    
    if not changes:
        raise InvalidInputError("NO_FIELDS", "直す項目が、1つも送られていません")

    current = repo.get_period_for_update(conn, period_id)
    if current is None:
        raise NotFoundError("PERIOD_NOT_FOUND", "シフト期間が見つかりません")

    # すでに発送済みなら、発送予定日時は直せない(案。仕様書8.2の#8bは未決)
    if "notify_at" in changes and current["notified_at"] is not None:
        raise ConflictError("NOTIFY_ALREADY_SENT", "すでに発送済みのため、発送予定日時は直せません")

    # 直したあとの値で、もう一度チェックする
    new_deadline = changes.get("submission_deadline", current["submission_deadline"])
    new_notify = changes.get("notify_at", current["notify_at"])
    _check_notify_before_deadline(new_notify, new_deadline)

    return repo.update_period(conn, period_id, changes)