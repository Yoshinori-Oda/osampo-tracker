# osampo-trackerバックエンドサーバーAPI設計ドラフト

このドキュメントにはサーバー側の挙動のみを記載する。クライアント(frontend)側で必要な対応は
`frontend/docs/ユーザー機能追加に伴う変更予定.md`を参照。

## server
url: http://localhost:8080/api

## 共通事項

### 認証と権限
- 401(認証できない): トークンがない、署名が不正、有効期限切れ、またはトークンの持ち主のユーザーが存在しない・無効化されている場合
  クライアントは再ログインを促す
- 403(権限がない): 認証はできたが、トークンのユーザーが管理者でなく、かつパスパラメーターのuser_idが自分自身でない場合
  再ログインしても結果は変わらない
- 上記の順に判定するので、一般ユーザーに404("user_not_found")が返ることはない(他ユーザーのuser_idを指定すると403で止まり、
  自分自身のユーザーが存在しなければ401で止まる)。404("user_not_found")が返るのは管理者が存在しないuser_idを指定した場合のみで、
  一般ユーザーには他ユーザーの存在有無が分からない
- パスパラメーターのuser_idは操作対象のユーザーを指定するためのもので、秘密の情報ではない(URLやログに残り、JWTの中身も
  暗号化されていない)。本人であることの確認はトークンの署名の検証のみで行う

### エラーレスポンス
- 4xx・5xxのレスポンスbodyは全て以下の形式で返す FastAPIが既定で返すエラー(バリデーションエラーの422、
  存在しないパスへの404など)も例外ハンドラーでこの形式に揃える
    ```
    {
        "code": "session_not_found",   (エラーの種類。クライアントはこれで処理を分岐する)
        "message": "..."   (人が読むための説明。クライアントは分岐に使わない)
    }
    ```
- 同じステータスコードでも意味が異なる場合があるため、クライアントが処理を分岐する必要があるエラーには必ず`code`を付ける。

### codeの一覧
| code | ステータス | 意味 |
| --- | --- | --- |
| `user_not_found` | 404 | パスパラメーターのuser_idのユーザーが存在しない |
| `session_not_found` | 404 | 当該ユーザーのsessionとして存在しない(パージ済み・未登録・他ユーザーのもの) |
| `id_conflicted` | 409 | 登録しようとしたidが別のsessionと衝突している |
| `deleted` | 409 | 対象のsessionが削除済み(tombstone)で、編集内容と競合している |

(401・403・413・415・422等のcodeはエラーハンドリングの実装時に決める)

## endpoints
- GET /users/{user_id}/sessions?last_synced_at=<日時>
    パスパラメーター:
        user_id: usersテーブルに登録されているid
    クエリパラメーター:
        last_synced_at: 最終同期時刻(absentを許容、Time Stamp (UTC))
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
                        "deleted_at": "2026-09-30T15:00:00.000Z"   (Time Stamp (UTC)、削除した日時)
                    },
                    ...
                ]
            }

    処理:
        1. トークンがない、あるいは無効だった場合: 401を返す
        2. user_id、またはlast_synced_atの書式が不正な場合、またはlast_synced_atがサーバー時刻より大きい場合: 422を返す
        3. header の認証情報に紐づいたユーザーが管理者でなく、かつuser_id と異なる場合: 403 を返す
        4. user_idが存在しない場合: 404("code": "user_not_found")を返す
        5. Acceptにapplication/jsonがない場合: 406を返す
        6. synced_atに現在のサーバー時刻(UTC)を入力する
        7. last_synced_atがabsent:　該当ユーザーのsessionのうちdeleted_atがnullのものを全て拾ってくる
           not absent: 該当ユーザーのsessionのうちupdated_atがlast_synced_atよりも後のものを全て拾ってくる
        8. last_synced_atがnot absentかつ(サーバー時刻 - パージ期間)より前: request_existence_checkをtrueにする
        9. json形式に変換して200で返す
    備考:
        - 現行実装のp_sync_timeは廃止する(サーバー時刻を基準とするため) リクエストした端末自身がpushしたsessionもレスポンスに含まれる
        - パージはdeleted_at(削除した日時)がパージ期間より古いtombstoneを物理削除する(現行のパージ期間は90日)
        - request_existence_checkがtrueの場合、パージ済みの削除はレスポンスに含まれない可能性がある(`POST /users/{user_id}/sessions/existence-check`で整合性チェックを行う)
        - sessionsの並び順はstarted_atの昇順
        - track_pointsの並び順はrecorded_atの昇順
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
            "name": "近所のお散歩",   (>= 1文字、<= 100文字)
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
        4. パスパラメーターのuser_idが存在しない場合: 404("code": "user_not_found")を返す
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

- PATCH /users/{user_id}/sessions/{session_id}
    パスパラメーター:
        user_id: usersテーブルに登録されているid
        session_id: 修正対象のsessionのid
    header:
        Authorization: Bearer <token>
        Content-Type: application/json
    body:
        {
            "name": "近所のお散歩",   (>= 1文字、<= 100文字)
            "move_method": "walk",   (walk, run, bicycle, car, train, plane, shipのいずれか)
            "is_favorite": true   (bool)
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
        4. パスパラメーターのuser_idが存在しない場合: 404("code": "user_not_found")を返す
        5. Content-Typeがapplication/jsonでない場合: 415を返す
        6. updated_atに現在のサーバー時刻(UTC)を入力する
        7. validationを行って不正があった場合: 422を返す
        8. sessionsテーブルをidとパスパラメーターのuser_idの両方で絞って検索し、該当するレコードがない場合: 404("code": "session_not_found")を返す
        9. 該当レコードのdeleted_atがnullでない場合: 409("code": "deleted")を返す
        10. 特定項目(\*2)が完全に一致する場合: レスポンスbodyのupdated_atを当該レコードのupdated_atに変更して200を返す
        11. 特定項目(\*2)が1つでも異なる場合: 特定項目(\*2)とupdated_atのみを更新して200を返す
    備考
        - bodyは特定項目(\*2)の3項目全てを必須とする(端末側で変更した項目を追跡しなくて済むようにするため)
        - 特定項目(\*2)以外の項目がbodyに含まれる場合は422を返す(Pydanticのextra="forbid"。端末のバグで不変の項目を変えようとしても気づけるようにするため)
        - 他ユーザーのsessionのidを指定した場合も、存在しない場合と区別せず404を返す(403を返すと、そのidのsessionを誰かが持っていることが分かってしまうため)
        - 3項目全てを毎回受け取るので、同じPATCHが2回届いても結果は変わらない
        - validationチェックの項目は以下の通り
            - session_idがUUID型である
            - 特定項目(\*2)の3項目が全て存在し、いずれもnullでない
            - nameが1文字以上100文字以内である
            - move_methodがwalk, run, bicycle, car, train, plane, shipのいずれかである
        - 409("deleted")はパージ前のtombstone、404("session_not_found")はパージ済み(または他ユーザーのもの・未登録)を表す
        - 同一ユーザーが複数端末で同時に操作することは想定しないため、競合の検出は削除済みかどうかのみで、他端末での編集は上書きする(楽観ロックは入れない)

- DELETE /users/{user_id}/sessions/{session_id}
    パスパラメーター:
        user_id: usersテーブルに登録されているid
        session_id: 削除対象のsessionのid
    header:
        Authorization: Bearer <token>
    body: なし

    レスポンス:
        body: なし

    処理:
        1. トークンがない、あるいは無効だった場合: 401を返す
        2. user_id、またはsession_idの書式が不正な場合: 422を返す
        3. header の認証情報に紐づいたユーザーが管理者でなく、かつパスパラメーターのuser_id と異なる場合: 403 を返す
        4. パスパラメーターのuser_idが存在しない場合: 404("code": "user_not_found")を返す
        5. sessionsテーブルをidとパスパラメーターのuser_idの両方で絞って検索し、該当するレコードがない場合: 404("code": "session_not_found")を返す
        6. 該当レコードのdeleted_atがnullでない場合: 何も変更せずに204を返す
        7. 該当レコードのdeleted_atとupdated_atに現在のサーバー時刻(UTC)を入力して204を返す
    備考
        - deleted_atは削除した日時(サーバー時刻)を表す(現行実装は削除予定時刻)
        - パージ(worker)はdeleted_atがパージ期間(90日)より古いtombstoneを物理削除する
        - 既にtombstoneの場合にdeleted_atを更新しないのは、パージまでの期間が延びることと、他端末に同じtombstoneが差分として再度届くことを避けるため
        - 該当レコードがない場合(パージ済み・未登録・他ユーザーのもの)を204ではなく404にするのは、PATCHと判定・エラーコードを揃え、
          将来ログを実装した際に「削除した」のか「元から無かった」のかを区別できるようにするため。
          どちらの場合もサーバーにそのsessionが存在しない状態になるので、同じDELETEを繰り返してもサーバーの状態は変わらない(冪等)
        - tombstoneになってもsessionとtrack_pointsのデータは残す(復活と、POSTの再送時の比較に必要なため)
        - 他端末での編集より後に届いた削除は、その編集を上書きして削除する(PATCHと同様、楽観ロックは入れない)

- POST /users/{user_id}/sessions/{session_id}/restore
    パスパラメーター:
        user_id: usersテーブルに登録されているid
        session_id: 削除を取り消す対象のsessionのid
    header:
        Authorization: Bearer <token>
        Content-Type: application/json
    body:
        {
            "name": "近所のお散歩",   (>= 1文字、<= 100文字)
            "move_method": "walk",   (walk, run, bicycle, car, train, plane, shipのいずれか)
            "is_favorite": true   (bool)
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
        4. パスパラメーターのuser_idが存在しない場合: 404("code": "user_not_found")を返す
        5. Content-Typeがapplication/jsonでない場合: 415を返す
        6. updated_atに現在のサーバー時刻(UTC)を入力する
        7. validationを行って不正があった場合: 422を返す(項目はPATCHと同じ)
        8. sessionsテーブルをidとパスパラメーターのuser_idの両方で絞って検索し、該当するレコードがない場合: 404("code": "session_not_found")を返す
        9. 該当レコードのdeleted_atがnullでない場合: deleted_atをnullにし、特定項目(\*2)とupdated_atを更新して200を返す
        10. 該当レコードのdeleted_atがnullの場合(復活済み): PATCHの手順10・11と同じ
            特定項目(\*2)が完全に一致する場合: レスポンスbodyのupdated_atを当該レコードのupdated_atに変更して200を返す
            特定項目(\*2)が1つでも異なる場合: 特定項目(\*2)とupdated_atのみを更新して200を返す
    備考
        - restoreは削除と編集が競合した際に編集内容を残して削除を取り消すためのエンドポイントで、編集項目と削除取り消しの両方を同時に行う
        - bodyの扱い(3項目全て必須、それ以外の項目は422)はPATCHと同じ
        - 処理名で終わるパスはリソースではなく操作を表すため、メソッドはPOSTとする
        - 既に復活済みの場合も200を返すので、同じrestoreを繰り返してもサーバーの状態は変わらない(冪等)
        - 復活したsessionはupdated_atが更新されるので、tombstoneを受け取ってローカルから削除していた他端末にも、
          次のGETで生きているsessionとして全データ(track_pointsを含む)が届き、復活する
        - 404("session_not_found")はパージ済みで、復活させる対象が残っていないことを表す
        - パージと同時に実行された場合は、トランザクションでどちらか一方が先に確定する。restoreが先ならdeleted_atがnullになり
          パージの対象から外れ、パージが先ならrestoreは404("session_not_found")になる

- POST /users/{user_id}/sessions/existence-check
    パスパラメーター:
        user_id: usersテーブルに登録されているid
    header:
        Authorization: Bearer <token>
        Content-Type: application/json
    body:
        {
            "session_ids": [
                "11111111-1111-1111-1111-111111111111",   (UUID)
                ...
            ]
        }

    レスポンス:
        header:
            Content-Type: application/json
        body:
            {
                "missing_session_ids": [
                    "11111111-1111-1111-1111-111111111111",   (UUID)
                    ...
                ]
            }

    処理:
        1. リクエストのbodyサイズが10MBを超える場合: 413を返す
        2. トークンがない、あるいは無効だった場合: 401を返す
        3. header の認証情報に紐づいたユーザーが管理者でなく、かつパスパラメーターのuser_id と異なる場合: 403 を返す
        4. パスパラメーターのuser_idが存在しない場合: 404("code": "user_not_found")を返す
        5. Content-Typeがapplication/jsonでない場合: 415を返す
        6. validationを行って不正があった場合: 422を返す
        7. session_idsのうち、当該ユーザーの生きている(deleted_atがnullの)sessionとして存在するものを検索する
        8. session_idsから7の結果を除いたものをmissing_session_idsとして200で返す
    備考
        - GETでrequest_existence_checkがtrueだった場合に、パージ済みで差分に含まれなかった削除を補うためのエンドポイント
        - DBは変更しないが、IDが多いとクエリ文字列の長さの上限にかかるためPOSTにする
        - tombstoneのsessionも「存在しない」として返す
        - 他ユーザーのsessionのIDも「存在しない」として返す(PATCH・DELETEの404と同様、他ユーザーのデータの有無を伝えないため)
        - 返すのは存在しないIDのみ。削除の漏れは通常ごく少数なので、レスポンスが小さくなる
        - IDの数に個別の上限は設けず、bodyの10MB制限のみとする(約25万件に相当し、個人のsession数では十分)
        - 重複したIDは1つにまとめて扱う。空の配列の場合は空のmissing_session_idsを200で返す
        - missing_session_idsの並び順は保証しない
        - サーバーは突き合わせの状態を持たない(どのGETに続く突き合わせかは関知しない)
        - validationチェックの項目は以下の通り
            - session_idsが存在し、配列である
            - session_idsの要素が全てUUID型である
