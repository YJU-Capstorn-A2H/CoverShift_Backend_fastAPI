"""希望提出API。受け取って、services に渡して、結果を返すだけ。"""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from app.core.db import get_conn
from app.schemas.availability import (
    AvailabilityIn,
    AvailabilityStatusOut,
    AvailabilitySubmitOut,
)
from app.services import availability_service
from app.services.errors import ServiceError

# API のルーティングをまとめる。URLの先頭に /api/staff をつける。
router = APIRouter(prefix="/api/staff", tags=["availability"])


# def _to_http：ServiceError を HTTPException に変換する
def _to_http(e: ServiceError) -> HTTPException:
    return HTTPException(status_code=e.status_code, detail={"code": e.code, "message": e.message})


# TODO(認証): いまは staff_id をURLで受け取るだけで、本人確認をしていない(開発用)。
#             マジックリンクのセッション確認(GET /api/pwa/session)を作ったら、
#             「ログイン中の本人の staff_id と一致するか」を、ここで確認する。
@router.post("/{staff_id}/availability", response_model=AvailabilitySubmitOut, status_code=201)
# staff_id は URL から、body は JSON から、conn は Depends(get_conn) で受け取る
def submit_availability(staff_id: UUID, body: AvailabilityIn, conn=Depends(get_conn)):
    try:
        return availability_service.submit(conn, staff_id, body)
    except ServiceError as e:
        raise _to_http(e)


# TODO(認証): 同上
@router.get("/{staff_id}/availability", response_model=AvailabilityStatusOut)
# staff_id と period_id は URL から、conn は Depends(get_conn) で受け取る
def get_availability_status(staff_id: UUID, period_id: UUID, conn=Depends(get_conn)):
    try:
        return availability_service.get_status(conn, staff_id, period_id)
    except ServiceError as e:
        raise _to_http(e)