"""希望提出まわりのSQL。ここはSQLを書くだけ(業務の判断はしない)。"""
import datetime as dt
from uuid import UUID
import psycopg


# COLUMNS：SQLで取り出したい列の名前を、1か所にまとめた「変数」
# _：「このファイルの中だけで使う変数」という意味。外部からは見えない。
_COLUMNS = "id, staff_id, period_id, date, start_time, end_time, submitted_at"


# get_staff：従業員情報を取得する
def get_staff(conn: psycopg.Connection, staff_id: UUID) -> dict | None:
    return conn.execute(
        "SELECT staff_id, " \
        "       is_active " \
        "FROM employees " \
        "WHERE staff_id = %s", (staff_id,)
    ).fetchone()


# get_period：シフト期間情報を取得する
def get_period(conn: psycopg.Connection, period_id: UUID) -> dict | None:
    return conn.execute(
        "SELECT period_id, " \
        "       period_start, " \
        "       period_end, " \
        "       submission_deadline "
        "FROM shift_periods " \
        "WHERE period_id = %s",
        (period_id,),
    ).fetchone()


# find_current_for_update：同じ人・同じ期間・同じ日の「最新の提出」を探す(置き換えられていないもの)
def find_current_for_update(
    conn: psycopg.Connection, staff_id: UUID, period_id: UUID, day: dt.date
) -> dict | None:
    """同じ人・同じ期間・同じ日の「最新の提出」を探す(置き換えられていないもの)。
    FOR UPDATE: 同時に2回送られても、順番に処理されるようロックする。"""
    return conn.execute(
        "SELECT id FROM availability_submissions "
        "WHERE staff_id = %s AND period_id = %s AND date = %s AND superseded_by IS NULL "
        "FOR UPDATE",
        (staff_id, period_id, day),
    ).fetchone()


# insert_submission：希望提出を登録する
def insert_submission(
    conn: psycopg.Connection,
    staff_id: UUID,
    period_id: UUID,
    day: dt.date,
    start_time: dt.time | None,
    end_time: dt.time | None,
) -> dict:
    return conn.execute(
        f"INSERT INTO availability_submissions (staff_id, period_id, date, start_time, end_time) "
        f"VALUES (%s, %s, %s, %s, %s) RETURNING {_COLUMNS}",
        (staff_id, period_id, day, start_time, end_time),
    ).fetchone()


# mark_superseded：古い提出に「この新しい提出に置き換えられた」と印をつける(履歴は消さない)
def mark_superseded(conn: psycopg.Connection, old_id: UUID, new_id: UUID) -> None:
    """古い提出に「この新しい提出に置き換えられた」と印をつける(履歴は消さない)。"""
    conn.execute(
        "UPDATE availability_submissions " \
        "SET superseded_by = %s " \
        "WHERE id = %s",
        (new_id, old_id),
    )


def list_current(conn: psycopg.Connection, staff_id: UUID, period_id: UUID) -> list[dict]:
    return conn.execute(
        f"SELECT {_COLUMNS} FROM availability_submissions "
        "WHERE staff_id = %s AND period_id = %s AND superseded_by IS NULL "
        "ORDER BY date",
        (staff_id, period_id),
    ).fetchall()