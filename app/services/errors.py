"""サービス層が投げる「業務上のエラー」。
routers がこれを受け取って、HTTPのエラーに変える。
detail の code は画面側が見分けるための英語コード(言語に依存しない)。
"""

class ServiceError(Exception):
    status_code = 400

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


# 探しているものがない（従業員、期間）
class NotFoundError(ServiceError):
    status_code = 404


# 入力のルール違反（日付が期間の外）
class InvalidInputError(ServiceError):
    status_code = 422


# 締切後の提出(いまは、許可されない)
class ForbiddenError(ServiceError):
    status_code = 403