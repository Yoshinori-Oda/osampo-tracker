from pydantic import BaseModel


class ErrorDetail(BaseModel):
    """入力チェックの失敗(422)で、どの項目がなぜ不正かを表す。"""

    # 不正だった項目の場所。"body.move_method"・"query.last_synced_at"・"path.session_id"のように、
    # 受け取った場所(body/query/path/header)と項目名をドットでつなぐ
    field: str
    reason: str


class ErrorResponse(BaseModel):
    """全てのエラーレスポンス(4xx・5xx)のbody。OpenAPIのドキュメントにも使う。"""

    code: str
    message: str
    # 422のときだけ入れる。それ以外のエラーではレスポンスに含めない
    details: list[ErrorDetail] | None = None
