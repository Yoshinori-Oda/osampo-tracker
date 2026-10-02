# osampo-trackerバックエンドサーバーAPI設計ドラフト

## server
url: http://localhost:8080/api

## endpoints
- GET /users/{user_id}/sessions?last_synced_at=<日時>
    パスパラメーター:
        user_id: usersテーブルに登録されているid
    クエリパラメーター:
        last_synced_at: 最終同期時刻(absentを許容、UTC(ISO 8601 拡張表示Zつき)で表現する)
    header: 
        Authorization: Bearer <token>
        Accept: application/json
    body: なし

    レスポンス:
        header: Content-Type: application/json
        body:
            {
                "synced_at": "2026-10-01T17:30:00.000Z",
                "request_existence_check": false,   (デフォルトはfalse)
                "sessions": [
                    {   (生きているレコードの場合)
                        "id": "11111111-1111-1111-1111-111111111111",   (UUID)
                        "name": "近所のお散歩",
                        "started_at": "2026-10-01T17:00:00.000Z",   (Time Stamp (UTC))
                        "ended_at": "2026-10-01T17:29:00.000Z",   (Time Stamp (UTC))
                        "is_favorite": true,   (bool)
                        "move_method": "walk",   (walk, run, bicycle, car, train, plane, shipのいずれか)
                        "total_distance": 2.0,　 ([km])
                        "duration_seconds": 1740,   ([sec])
                        "elevation_gain": 50.0,   ([m])
                        "max_altitude": 30.0,　(nullable, [m])
                        "min_altitude": 7.5,  (nullable, [m])
                        "updated_at": "2026-10-01T17:30:00.000Z",   (Time Stamp (UTC))
                        "track_points": [
                            {"recorded_at": "2026-10-01T17:00:00.000Z",    (Time Stamp (UTC))
                            "latitude": 37.33003773,
                            "longitude": -122.02088037,
                            "altitude": 12.5},  (nullable, [m])
                            ...
                        ]
                    },
                    {   (削除されたレコードの場合、last_synced_atがnot absentの時のみ)
                        "id": "11111111-1111-1111-1111-111111111111",   (UUID)
                        "deleted_at": "2026-09-30T15:00:00.000Z"
                    },
                    ...
                ]
            }

    処理:
        1. トークンがない、あるいは無効だった場合: 401を返す
        2. user_id、またはlast_synced_atの書式が不正な場合、またはlast_synced_atがサーバー時刻より大きい場合: 422を返す
        3. header の認証情報に紐づいたユーザーが管理者でなく、かつuser_id と異なる場合: 403 を返す
        4. user_idが存在しない場合: 404を返す
        5. Acceptにapplication/jsonがない場合: 406を返す
        6. synced_atに現在のサーバー時刻(UTC)を入力する
        7. last_synced_atがabsent:　該当ユーザーのsessionのうちdeleted_atがnullのものを全て拾ってくる
           not absent: 該当ユーザーのsessionのうちupdated_atがlast_synced_atよりも後のものを全て拾ってくる
        8. last_synced_atがnot absentかつ(パージ期間 - パージ頻度)以上: request_existence_checkをtrueにする
        9. json形式に変換して200で返す
    備考:
        - 現行実装のp_synced_atは廃止(サーバー時間を基準とするため、自分がpushしたsessionも返ってくるが同じ内容で上書きしても問題ない)
        - 現行実装ではパージ期間は90日、パージ頻度は1日である
        - request_existence_checkがtrueのときはパージ期間を超過した(tombstoneがない削除済みの)セッションを確認する処理を行う(詳細は{後から考えるエンドポイント}を参照)
        - sessionsの並び順はstarted_atの昇順
        - track_pointsの並び順はrecorded_atの昇順
        - パージ期間以上の再同期について、last_synced_atを更新するのは削除済みのsessionsを突き合わせた後とする(失敗した時に再チェックができなくなるため)
        - ユーザー機能が実装されていない間はトークンの検証をスルーする形とする
        - ページングは未定(このドキュメントが正式版になるまでには決定予定)

- POST /users/{user_id}/sessions
    パスパラメーター:
        user_id: usersテーブルに登録されているid
    header:
        Authorization: Bearer <token>
        Content-Type: application/json
    body:
        {
            "id": "11111111-1111-1111-1111-111111111111",   (UUID)
            "name": "近所のお散歩",   (<= 100文字)
            "started_at": "2026-10-01T17:00:00.000Z",   (Time Stamp (UTC))
            "ended_at": "2026-10-01T17:29:00.000Z",   (Time Stamp (UTC))
            "is_favorite": true,   (bool)
            "move_method": "walk",   (walk, run, bicycle, car, train, plane, shipのいずれか)
            "total_distance": 2.0,   ([km])
            "duration_seconds": 1740,   ([sec])
            "elevation_gain": 50.0,   ([m])
            "max_altitude": 30.0,   (nullable, [m])
            "min_altitude": 7.5,   (nullable, [m])
            "track_points": [
                {
                    "recorded_at": "2026-10-01T17:00:00.000Z",   (Time Stamp (UTC))
                    "latitude": 37.33003773,   (double precision, -90~90)
                    "longitude": -122.02088037,   (double precision, -180~180)
                    "altitude": 12.5   (nullable, [m])
                },
                ...
            ]
        }

    レスポンス:
        header:
            Content-Type: application/json
        body:
            {
                "updated_at": "2026-10-01T17:30:00.000Z"   (Time Stamp (UTC))
            }
    
    処理:
        1. リクエストのbodyサイズが10MBを超える場合: 413を返す
        2. トークンがない、あるいは無効だった場合: 401を返す
        3. header の認証情報に紐づいたユーザーが管理者でなく、かつパスパラメーターのuser_id と異なる場合: 403 を返す
        4. パスパラメーターのuser_idが存在しない場合: 404を返す
        5. Content-Typeがapplication/jsonでない場合: 415を返す
        6. updated_atに現在のサーバー時刻(UTC)を入力する
        7. validationを行って不正があった場合: 422を返す
        8. sessionsテーブル(全ユーザー)でidが等しいレコードがあった場合:
            他ユーザーのレコードだった場合、または特定項目(\*1)が1つでも異なる場合: 409("code": "id_conflicted")を返す
            当該ユーザーのレコードであり、特定項目(\*1)が完全に一致する場合:
                該当レコードのdeleted_atがnullでない場合:
                    特定項目(\*2)が1つでも異なる場合: 409("code": "deleted")を返す
                    特定項目(\*2)が完全に一致する場合: レスポンスbodyのupdated_atを当該レコードのupdated_atに変更して200を返す
                該当レコードのdeleted_atがnullの場合:
                    特定項目(\*2)が1つでも異なる場合: 特定項目(\*2)とupdated_atのみを更新して200を返す
                    特定項目(\*2)が完全に一致する場合: レスポンスbodyのupdated_atを当該レコードのupdated_atに変更して200を返す
        9. 登録処理を行い201を返す
    備考
        - updated_atはsessionのupdated_at用であり、last_synced_atは後続のGETリクエストから更新する
        - リモートDBには終了したセッションのみを記録する方針なので、ended_atはnon-nullとする
        - uvicornとFastAPIは仕様上リクエストサイズの制限がないため、不正なリクエストによって処理が停滞しないようにbodyに10MBの制限をかける
        - 特定項目\*1: started_at, ended_at, total_distance, duration_seconds, elevation_gain, max_altitude, min_altitude
        - 特定項目\*2: name, is_favorite, move_method
        - 現行のDB設定ではelevation_gain, max_altitude, min_altitudeがREALなのでマイグレーションでdouble precisionに変更する必要がある
        - max_altitude, min_altitudeの比較時にnullチェックが必要(SQLではNULL = NULLが真にならない)
        - validationチェックの項目は以下の通り
            - idがUUID型である
            - nameが1文字以上100文字以内である
            - ended_atがstarted_at以降である
            - move_methodがwalk, run, bicycle, car, train, plane, shipのいずれかである
            - total_distance, duration_seconds, elevation_gainが0以上
            - latitudeが-90~90, longitudeが-180~180
            - nullはmax_altitude, min_altitude, altitudeのみ許す
        - 万が一同時に同じIDのセッションが登録されようとした時のために、登録処理はINSERT ... ON CONFLICT DO NOTHINGで行い、DO NOTHINGで挿入が0件の場合は手順8からやり直す
        - セッションとトラックポイントは1つのトランザクションで登録する
