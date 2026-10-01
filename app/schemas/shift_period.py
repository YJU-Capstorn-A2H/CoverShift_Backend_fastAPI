"""シフト期間API(管理者用)の、リクエストとレスポンスの形。"""
import datetime as dt
from uuid import UUID
from pydantic import BaseModel, Field, field_validator, model_validator


# 「タイムゾーン付きの日時」を必須にする。タイムゾーンなしだと、どこの国の時刻かわからないので、エラーにする
def _require_timezone(v: dt.datetime | None) -> dt.datetime | None:
    # 「9/25 23:59」だけだと、どこの国の時刻かわからない。+09:00 などを必須にする(案)
    if v is not None and v.utcoffset() is None:
        raise ValueError("タイムゾーンを付けてください(例: 2026-10-20T23:59:00+09:00)")
    return v

# period_start と period_end の大小関係をチェックする
class ShiftPeriodCreate(BaseModel):
    period_start: dt.date
    period_end: dt.date
    submission_deadline: dt.datetime
    notify_at: dt.datetime
    max_revision: int = Field(default=2, ge=1, le=5)  # 再調整の上限(1〜5)

    _tz = field_validator("submission_deadline", "notify_at")(_require_timezone)

    # period_start と period_end の大小関係をチェックする
    @model_validator(mode="after")
    def check_dates(self):
        if self.period_end < self.period_start:
            raise ValueError("period_end は period_start と同じか、それより後にしてください")
        return self


# 「直したい項目だけを送る。送らなかった項目は、そのまま。」
class ShiftPeriodPatch(BaseModel):
    submission_deadline: dt.datetime | None = None
    notify_at: dt.datetime | None = None
    max_revision: int | None = Field(default=None, ge=1, le=5)

    _tz = field_validator("submission_deadline", "notify_at")(_require_timezone)


# 「返すときの形」を定義する。DBのカラム名と同じにしておくと、DBから直接返せるので便利
class ShiftPeriodOut(BaseModel):
    period_id: UUID
    period_start: dt.date
    period_end: dt.date
    submission_deadline: dt.datetime
    notify_at: dt.datetime
    notified_at: dt.datetime | None  # 実際に発送した日時(まだなら None)
    max_revision: int
    created_at: dt.datetime