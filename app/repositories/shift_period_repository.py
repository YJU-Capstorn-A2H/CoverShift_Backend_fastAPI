"""シフト期間まわりのSQL。ここはSQLを書くだけ(業務の判断はしない)。"""
from uuid import UUID
import psycopg


_COLUMNS = (
    "period_id, period_start, period_end, submission_deadline, "
    "notify_at, notified_at, max_revision, created_at"
)

# 直してよい列(これ以外の名前はSQLに入れない = SQLインジェクション対策)
_UPDATABLE = ("submission_deadline", "notify_at", "max_revision")


# 「新しい期間を作る」INSERT
def insert_period(conn: psycopg.Connection, values: dict) -> dict:
    # TODO(認証): created_by(作成した管理者)は、管理者ログインを作ったら入れる
    return conn.execute(
        f"INSERT INTO shift_periods "
        f"(period_start, period_end, submission_deadline, notify_at, max_revision) "
        f"VALUES (%(period_start)s, %(period_end)s, %(submission_deadline)s, %(notify_at)s, %(max_revision)s) "
        f"RETURNING {_COLUMNS}",
        values,
    ).fetchone()


# 「期間の一覧を返す」SELECT
def list_periods(conn: psycopg.Connection) -> list[dict]:
    return conn.execute(
        f"SELECT {_COLUMNS} FROM shift_periods ORDER BY period_start DESC, created_at DESC"
    ).fetchall()


# 「期間の1行を返す」SELECT
def get_period_for_update(conn: psycopg.Connection, period_id: UUID) -> dict | None:
    """直す前に、その行をロックして読む(同時に2人が直しても、順番に処理される)。"""
    
    return conn.execute(
        f"SELECT {_COLUMNS} FROM shift_periods WHERE period_id = %s FOR UPDATE", (period_id,)
    ).fetchone()


# 「期間を更新する」UPDATE
def update_period(conn: psycopg.Connection, period_id: UUID, changes: dict) -> dict:
    cols = [c for c in _UPDATABLE if c in changes]
    set_sql = ", ".join(f"{c} = %({c})s" for c in cols)

    return conn.execute(
        f"UPDATE shift_periods SET {set_sql} WHERE period_id = %(period_id)s RETURNING {_COLUMNS}",
        {**{c: changes[c] for c in cols}, "period_id": period_id},
    ).fetchone()