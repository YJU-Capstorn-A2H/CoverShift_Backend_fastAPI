"""シフト期間API(管理者用)。受け取って、services に渡して、結果を返すだけ。"""
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException
from app.core.db import get_conn
from app.schemas.shift_period import ShiftPeriodCreate, ShiftPeriodOut, ShiftPeriodPatch
from app.services import shift_period_service
from app.services.errors import ServiceError

router = APIRouter(prefix="/api/admin/shift-periods", tags=["admin: shift-periods"])


# ServiceError を HTTPException に変える
def _to_http(e: ServiceError) -> HTTPException:
    return HTTPException(status_code=e.status_code, detail={"code": e.code, "message": e.message})


# TODO(認証): 管理者ログイン(JWT)を作ったら、3つのAPI全部で「管理者か」を確認する。
#             いまは、誰でも呼べる(開発用)。
@router.post("", response_model=ShiftPeriodOut, status_code=201)
def create_period(body: ShiftPeriodCreate, conn=Depends(get_conn)):
    try:
        return shift_period_service.create(conn, body)
    
    except ServiceError as e:
        raise _to_http(e)


# 「期間の一覧を返す」
@router.get("", response_model=list[ShiftPeriodOut])
def list_periods(conn=Depends(get_conn)):
    return shift_period_service.list_all(conn)


# 「期間を更新する」
@router.patch("/{period_id}", response_model=ShiftPeriodOut)
def update_period(period_id: UUID, body: ShiftPeriodPatch, conn=Depends(get_conn)):
    try:
        return shift_period_service.update(conn, period_id, body)
    
    except ServiceError as e:
        raise _to_http(e)