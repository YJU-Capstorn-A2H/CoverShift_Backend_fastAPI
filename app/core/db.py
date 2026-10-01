"""DB接続。psycopg(SQLを直接書く方式)の「接続プール」を1つ持つ。

接続プール = 接続をいくつか使い回す仕組み。
リクエストのたびに接続を作り直すと遅いので、あらかじめ数本つないでおく。
"""
import os
from collections.abc import Iterator
import psycopg
from dotenv import load_dotenv
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

# .env を読む(main.py より先に import されても大丈夫なよう、ここでも呼ぶ)
load_dotenv()

_database_url = os.environ.get("DATABASE_URL")
if not _database_url:
    raise RuntimeError(".env に DATABASE_URL がありません。.env.example を見て追加してください。")

# 起動時に open_pool() で作る。閉じたプールは開き直せないので、
# 起動のたびに新しく作る(テストで何度も起動・終了しても壊れないようにするため)
pool: ConnectionPool | None = None



# DB接続プールを起動する
def open_pool() -> None:
    global pool
    pool = ConnectionPool(
        _database_url,
        min_size=1,
        max_size=5,
        kwargs={"row_factory": dict_row},  # 結果を {"列名": 値} の辞書で受け取る
        open=False,
    )
    pool.open(wait=True, timeout=10)


# DB接続プールを閉じる
def close_pool() -> None:
    global pool
    if pool is not None:
        pool.close()
        pool = None

# DB接続を取得する
def get_conn() -> Iterator[psycopg.Connection]:
    """FastAPIの Depends 用。1リクエスト = 1接続。

    - 正常に終われば commit(確定)
    - 例外が起きれば rollback(取り消し)
    をpoolが自動でやってくれる。
    """
    if pool is None:
        raise RuntimeError("DBプールが未起動です(open_pool() が呼ばれていません)")
    with pool.connection() as conn:
        yield conn