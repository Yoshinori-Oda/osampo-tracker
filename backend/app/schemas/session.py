"""同期APIのリクエスト/レスポンスの型と入力チェック。仕様はbackend/docs/API設計ドラフト.mdを参照。

日時はタイムゾーン付き(AwareDatetime)のみ受け付ける("Z"や"+09:00"の無い日時は422)。
"""

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StringConstraints, model_validator


class MoveMethod(StrEnum):
    """移動手段。frontendのMoveMethod(lib/models/move_method.dart)と同じ値にする。"""

    WALK = "walk"
    RUN = "run"
    BICYCLE = "bicycle"
    CAR = "car"
    TRAIN = "train"
    PLANE = "plane"
    SHIP = "ship"


SessionName = Annotated[str, StringConstraints(min_length=1, max_length=100)]


# ---- リクエスト ------------------------------------------------------------------


class TrackPointIn(BaseModel):
    recorded_at: AwareDatetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    # 単位はm。キーは必須だがnullを許す
    altitude: float | None


class SessionCreate(BaseModel):
    """POST /users/{user_id}/sessions のbody。nullを許すのはmax_altitude・min_altitudeのみで、キーは全て必須。"""

    id: uuid.UUID
    name: SessionName
    started_at: AwareDatetime
    ended_at: AwareDatetime
    is_favorite: bool
    move_method: MoveMethod
    total_distance: float = Field(ge=0)  # km
    duration_seconds: int = Field(ge=0)
    elevation_gain: float = Field(ge=0)  # m
    max_altitude: float | None  # m
    min_altitude: float | None  # m
    track_points: list[TrackPointIn]

    @model_validator(mode="after")
    def ended_at_must_not_be_before_started_at(self) -> Self:
        if self.ended_at < self.started_at:
            raise ValueError("ended_atはstarted_at以降にしてください")
        return self


class SessionEdit(BaseModel):
    """PATCH・restoreのbody。可変の3項目のみで全て必須。それ以外の項目が含まれていれば422にする。"""

    # 端末のバグで不変の項目(started_at等)を変えようとしても気づけるよう、知らない項目は拒否する
    model_config = ConfigDict(extra="forbid")

    name: SessionName
    move_method: MoveMethod
    is_favorite: bool


class ExistenceCheckRequest(BaseModel):
    session_ids: list[uuid.UUID]


# ---- レスポンス ------------------------------------------------------------------


class TrackPointOut(BaseModel):
    recorded_at: datetime
    latitude: float
    longitude: float
    altitude: float | None


class SessionOut(BaseModel):
    """GETで返す生きているsession。"""

    id: uuid.UUID
    name: str
    started_at: datetime
    ended_at: datetime
    is_favorite: bool
    move_method: str
    total_distance: float
    duration_seconds: int
    elevation_gain: float
    max_altitude: float | None
    min_altitude: float | None
    updated_at: datetime
    track_points: list[TrackPointOut]


class DeletedSessionOut(BaseModel):
    """GETで返す削除済みのsession(tombstone)。last_synced_atを指定した場合のみ返す。"""

    id: uuid.UUID
    deleted_at: datetime  # 削除した日時


class SyncResponse(BaseModel):
    # 次回のGETでlast_synced_atとして送る値(検索を始める前のサーバー時刻)
    synced_at: datetime
    # trueのときは、パージ済みの削除がsessionsに含まれていない可能性があるので、existence-checkで突き合わせる
    request_existence_check: bool
    sessions: list[SessionOut | DeletedSessionOut]


class UpdatedAtResponse(BaseModel):
    """POST・PATCH・restoreのレスポンス。端末はこの値をそのsessionのupdated_atとして保存する。"""

    updated_at: datetime


class ExistenceCheckResponse(BaseModel):
    # 当該ユーザーの生きているsessionとして存在しないID(並び順は保証しない)
    missing_session_ids: list[uuid.UUID]
