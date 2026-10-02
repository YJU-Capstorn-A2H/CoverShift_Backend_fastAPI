"""希望提出APIの、リクエストとレスポンスの形(入力チェックもここ)。"""
import datetime as dt 
from uuid import UUID # 外部侵入を防ぐためのランダム文字列にする。ユーザーIDや希望IDなどの識別子に使う。
from pydantic import BaseModel, model_validator


class AvailabilityIn(BaseModel):
    """1日分の希望。start_time と end_time が両方とも空なら「休み希望」。"""

    period_id: UUID
    date: dt.date
    start_time: dt.time | None = None
    end_time: dt.time | None = None

    @model_validator(mode="after")
    def check_times(self):
        if (self.start_time is None) != (self.end_time is None):
            raise ValueError("start_time と end_time は、両方入れるか、両方空(休み希望)にしてください")
        if self.start_time is not None and self.end_time <= self.start_time:
            raise ValueError("end_time は start_time より後にしてください")
        return self


class AvailabilityOut(BaseModel):
    id: UUID
    staff_id: UUID
    period_id: UUID
    date: dt.date
    start_time: dt.time | None
    end_time: dt.time | None
    submitted_at: dt.datetime
    is_late: bool  # 締切のあとの提出なら True(変更リクエスト扱い。拒否はしない)


class AvailabilitySubmitOut(AvailabilityOut):
    replaced_previous: bool  # 同じ日の前の提出を、置き換えたか


class AvailabilityStatusOut(BaseModel):
    period_id: UUID
    submission_deadline: dt.datetime
    total_days: int       # 対象期間の日数
    submitted_days: int   # 入力済みの日数(最新の提出がある日)
    items: list[AvailabilityOut]