# バックエンド構成・ユーザー機能の検討メモ

2026-09-29時点の検討内容。背景は`CLAUDE.md`の「キャッチアップの状況と方針」、日程は`docs/plans/roadmap.md`を参照。

## 位置づけ

想定しているリリース形態(ローカルのみで完結)ではユーザー機能は不要。それでも、上長の指示にある
「REST API連携(認証トークンの付与)」と、本案件の「認証・管理者」要件のキャッチアップのために取り組む。
主目的は実装経験を積むことより、本案件の要件定義に向けて制約(実装すべきこと/できないこと)を理解すること。
リリース版では同期・ログインを無効化する(`docs/plans/release-plan.md`)。

## 現状(着手前)

- ユーザーIDは`frontend/lib/providers/tracking_providers.dart`に`11111111-...`として直書き
- `users`テーブルは`id / email / created_at`のみで、パスワードは持たない
- PostgRESTはJWT未設定で、全リクエストが`web_anon`として動く。`web_anon`は全テーブルに`GRANT ALL`
- `register_session_with_points`(SECURITY DEFINER)と`fetch_remote_sessions`は、クライアントが
  送った`user_id`をそのまま信用している。他人の`user_id`を送れば他人のデータを読み書きできる
- 削除tombstoneのパージは別イメージのcronコンテナで行い、複雑な処理はstored functionに押し込んでいる

## バックエンド構成(2026-09-29決定)

PostgRESTをやめ、**PythonのAPIサーバー(FastAPI)**に置き換える。DBはPostgreSQL/PostGISを継続する
(本案件もPostgreSQL、おそらくAmazon Auroraの見込み)。

選んだ理由:

- ユーザーは比較的Pythonに慣れているので、理解のコストが低い(APIサーバーは未経験。Webサーバーの
  経験はJava研修でのSpringのみ)
- リクエストの型検証とOpenAPIのAPI仕様書が自動で生成されるので、API設計として何を決める必要が
  あるかが見えやすく、要件定義の練習素材になる
- 認証・メール送信・定期実行を1つのコードベースにまとめられる

見送った候補: Node.js(実用的だが学習コストが重い)、Dart(主目的に対して必須でない)、
PostgREST継続+送信ワーカー(認証がPL/pgSQLに埋まり見通しが悪い)、Supabase(自前実装の方針に反する)。

### サービス構成(docker compose)

| サービス | 役割 |
|---|---|
| `db` | PostgreSQL/PostGIS(既存) |
| `api` | uvicornでFastAPIを常駐させ、エンドポイントを提供する(`restart: unless-stopped`) |
| `worker` | `api`と同じイメージ・同じコードで、起動コマンドだけ変える。メール送信(outbox)とパージを定期実行する |
| `mailpit` | 開発用のSMTP受信サーバーとWeb UI。外部にメールを出さない |

`postgrest`と`cron`は削除する。

- 定期実行を`api`と同じプロセスで動かさないのは、ワーカー数を増やしたときにジョブが重複して走るため
- DBへはcomposeのネットワーク内でサービス名`db`で接続する
- 依存パッケージはイメージのビルド時に入れる。devcontainerにはPython 3.11があるがpipが無く、
  「コンテナにプロジェクト固有のSDKを入れない」方針なので環境は追加しない。サーバーの起動・テストは
  ホスト側の`docker compose`(例: `docker compose run --rm api pytest`)で行う
- スキーマはAlembicのマイグレーションで管理する。今の`initdb.sql`はDROPしてから作り直す方式で、
  本番では使えないため

### パッケージ

バージョンと保守状況は着手時に確認する。

| 役割 | パッケージ | Springで言うと |
|---|---|---|
| Webフレームワーク(ルーティング、依存注入) | FastAPI | Spring MVC、`@RestController`、DI |
| サーバー本体(常駐プロセス) | uvicorn | 組み込みTomcat |
| リクエスト/レスポンスの型と検証 | Pydantic(FastAPIに同梱) | Bean ValidationとDTO |
| 設定・秘密情報の読み込み(`.env`) | pydantic-settings | `application.properties` |
| DBドライバ | psycopg(v3) | JDBCドライバ |
| ORMとクエリ | SQLAlchemy 2.x | JPA/Hibernate |
| PostGISの型 | GeoAlchemy2 | Hibernate Spatial |
| スキーマのマイグレーション | Alembic | Flyway/Liquibase |
| パスワードハッシュ | pwdlib[argon2](passlibは保守が止まっているので使わない) | Spring SecurityのPasswordEncoder |
| JWTの発行・検証 | PyJWT | Spring Security + jjwt |
| メール送信 | 標準ライブラリのsmtplib(必要ならaiosmtplib) | JavaMailSender |
| 定期実行 | APScheduler(`worker`内) | `@Scheduled` |
| テスト | pytest + FastAPIの`TestClient` | JUnit + MockMvc |
| パッケージ管理・lock | uv(`pyproject.toml` + `uv.lock`) | Maven/Gradle |
| lint・フォーマット | ruff | Checkstyle等 |

## 決定事項

- 認証基盤は外部サービス(Firebase Auth等)を使わず**自前で実装**し、仕組みを理解する
- パスワードの検証はサーバー側だけで行う。端末にはパスワードを保存せず、トークンだけを
  `flutter_secure_storage`(Keychain/Keystore)に保存する
- 同期は**ログイン中のユーザーのレコードだけ**を切り出す。user_idはクライアントの申告ではなく
  トークンから決める
- ローカルデータはユーザーごとに分けて保持する(1台の端末で複数アカウントを使い分けることは
  想定しないが、セッションにユーザーが紐づいているため)
- トークンが切れていても記録・閲覧はでき、止まるのは同期だけにする(オフラインファーストを維持)
- メール確認を入れる。確認方法はリンクではなく6桁コードの入力にする(Universal Links/App Links
  の設定を避けるため)
- ログイン中のパスワード変更は現在のパスワードで確認する(メール不要)。メールが必要なのは忘れたときの
  リセットだけ
- QR読取機能は入れない(本案件の要件に寄りすぎていて、このアプリでの使い道に無理がある)
- SNS的な拡張(bio・フォロー/フォロワー)はやらない。表示名だけ持つ
- リフレッシュトークンを入れる(2026-10-06決定。現代的な認証のスタンダードとして倣い、仕組みを学んでおくため)。
  期限切れのアクセストークンには401(`token_expired`)を返し、端末は再ログインではなくトークンの更新を行う

- サインアップは**メール確認付きの自由登録**にする(2026-10-07決定。個人向けアプリには管理者招待型より自由登録が合う。
  本案件は管理者招待型に近くなりそう)
- 認証の詳細(2026-10-07〜08に設計): パスワードは8〜128文字・MFAなし、アクセストークンはES256のJWT(15分)、
  リフレッシュトークンは256ビットの乱数(30日・使うたびに取り替え・使用済みが使われたらその端末のログイン状態を無効にする)、
  端末ごとのログイン状態とトークンの系列をセットで持ちアクセストークンも毎回DBで突き合わせる、アカウントの削除は関連データごと物理削除、
  メールアドレスの確認前もログインできるが同期はできない、データの分離はアプリ層(RLSは後で追加)。
  仕様は`backend/docs/API設計ドラフト.md`、実装方針は`backend/docs/バックエンド構成.md`の「認証」、
  frontendは`frontend/docs/ユーザー機能追加に伴う変更予定.md`の「認証(ブロック2)」
- ゲストの代わりに**ローカルアカウント**(同期しないアカウント。複数作れる・通常のアカウントと相互に変更できる)を後で作る
  (2026-10-08決定)。ブロック2では起動時に通常のアカウントでのログインか登録を求める
- ローカルアカウントの設計(2026-10-27): ローカル→通常は新規登録に加えて既存の通常のアカウントへのログインでの合流もできるようにし、
  `users.id`の書き換えではなくsessionsの付け替えで行う。アカウントの切り替え・ローカル→通常は収録中はできず、通常→ローカルは収録中もできる
  (2026-10-28に実装。ブランチ`feat/local-account`)。
  通常のアカウントでログアウトした後はログイン画面を出す。リリース版は`--dart-define`で同期の機能を隠す。
  詳細は`frontend/docs/ユーザー機能追加に伴う変更予定.md`の「ローカルアカウント」

## 未決事項

(2026-10-08時点で無し)

## 作業の洗い出し

`docs/plans/roadmap.md`のブロックとの対応を括弧で示す。

### 10/29まで

バックエンドの置き換え(ブロック1):

- [ ] FastAPIの土台: uv、Dockerfile、composeの4サービス構成、pydantic-settings、秘密情報(DBパスワード、
      JWT署名鍵、SMTP設定)の`.env`化
- [ ] Alembicで既存スキーマ(sessions/track_points/users、PostGIS)を初期マイグレーションにする
- [ ] 同期APIの移植: 登録(トラックポイント込み)、差分取得、`deleted_at`条件付きの更新、削除tombstone、
      復活。既存の挙動(競合検出を含む)をpytestで確認する
- [x] パージ処理を`worker`に移し、`postgrest`/`cron`を削除する
- [x] フロントの接続先(`TrackingRepository`)を新しいAPIに切り替える
- [x] `run_checks.sh`にbackendのステップを追加する
- [x] OpenAPIのAPI仕様を見直し、API設計として整理する

(ブロック1は2026-10-06に完了)

認証の中核(ブロック2):

(2026-10-08に実装。backendは`feat/auth-backend`、frontendは`feat/auth-frontend`。mainに取り込み済み)

- [x] `users`の拡張: `password_hash`, `display_name`, `email_verified_at`, `role`(user/admin),
      `disabled_at`, `updated_at`
- [x] パスワードのハッシュ化、サインアップ・ログインAPI(ES256のJWTの発行)、認証の依存注入(トークンからユーザーを決める)
- [x] 端末ごとのログイン状態(`auth_sessions`)と、アクセストークンの`sid`の毎回の突き合わせ、ログアウト
- [x] `GET`/`PATCH`/`DELETE /users/me`(表示名の変更、アカウントの物理削除)
- [x] メールアドレスが未確認のユーザーの同期を403(`email_not_verified`)にする
- [x] リフレッシュトークン: 発行・更新(ローテーション)・失効(ログアウト)と、その保存方法。フロントは`token_expired`の
      401を受けたらトークンを更新して元のリクエストをやり直す
- [x] 同期APIを本人の行だけに制限する(アプリ層。パスのuser_idとトークンのユーザーを比べる。RLSは後で追加)
- [x] ロール(一般ユーザー/管理者)で操作できる範囲を分ける
- [x] シード: 初期の管理者と、パスワード付きのテストユーザー。既存テストデータ(`1111...`)の移行
- [x] テスト: ユーザーAのトークンでBのデータを読み書きできないこと、ロールの境界、トークン切れ・改ざん
- [x] フロント: 認証provider(直書きの`userId`を置き換える)、`flutter_secure_storage`、ログイン画面と
      未ログイン時の誘導、`Authorization: Bearer`の付与、401のときは再ログインを促しデータは消さない
- [x] フロント: ローカルDBの移行(`users`テーブル、`sessions.user_id`の外部キー、`PRAGMA foreign_keys = ON`、
      `last_synced_at`を`users`へ)とユーザー別のデータ分離。ログアウト前に同期を試し、失敗したらスナックバーで警告する
- [x] フロント: 端末ID(初回起動時のUUID)、新規登録画面、アカウントの削除
- [x] フロント: トークンが切れていても記録・閲覧できること
- [x] フロントのテスト: 認証provider/リポジトリのユニットテスト、ログイン画面のウィジェットテスト
      (ログイン画面・AuthGateのウィジェットテストは2026-10-23に追加し、雛形のまま壊れていた`widget_test.dart`を消した)

メールとアカウント(ブロック3):

- [x] メール送信基盤: outboxテーブル + `worker`での送信 + Mailpit(2026-10-14。ブランチ`feat/mail-outbox`、run_id `c5dd5ba8`でPASSED、Mailpitでの送信・再送を確認済み)
- [x] メール確認コード(サインアップ自体はブロック2。6桁・10分・5回まで・再送は60秒あけて1日5回まで、argon2で保存)(backendは2026-10-14。ブランチ`feat/email-verification-code`、run_id `53c4a25b`でPASSED。画面は下の「フロント: サインアップ/確認コード入力の画面」)
- [x] パスワード変更(現在のパスワードで確認)(2026-10-14。ブランチ`feat/password-change`、backendはrun_id `d4877cba`、frontendは`75aadd16`でPASSED。この端末以外のログイン状態の無効化と変更の通知メールも。2台の端末での確認は未実施)
- [x] フロント: サインアップ/確認コード入力の画面(再送を含む)(2026-10-14。ブランチ`feat/email-verification-screen`、run_id `735b882d`でPASSED、シミュレータでMailpitのコードによる確認まで確認済み)
- [x] 設定タブ: 全体の構成を設計し、アカウント欄(表示名の編集、パスワード変更、ログアウト)を実装する(2026-10-14。ブランチ`feat/password-change`、frontendはrun_id `75aadd16`でPASSED。構成は`docs/design/screens.md`の`settings_page.dart`)

### 11月以降

- [ ] パスワードリセット(メールのコードで確認)
- [ ] メールアドレス変更(新しいアドレスに確認コードを送る)
- [ ] ローカルアカウント(同期しないアカウント。作成・切り替え・通常との相互の変更。`frontend/docs/ユーザー機能追加に伴う変更予定.md`)
- [x] RLS(2026-10-26。`sessions`・`track_points`のみ。worker用のロールも分けた)
- [ ] 管理者API・メニュー: 招待の発行、ユーザー一覧、アカウントの無効化(設定タブ内、管理者のときだけ表示)
- [ ] 設定タブの残り(リセットへの導線、メールアドレス変更。アカウント削除はブロック2で実装済み)

### 2次

- [x] 監査ログ(ログイン成功/失敗、招待、パスワード変更、管理者の操作)(2026-10-23。ブランチ`feat/audit-log`。招待は機能ができたら加える)
- [x] ログイン試行回数の制限(監査ログの失敗記録を使ってロック)(2026-10-23。ブランチ`feat/login-attempt-limit`。ログインと
      パスワードの変更での再確認は別に数える)
- [ ] 端末の登録・識別の拡張(端末の一覧・端末ごとのログアウトの画面。端末ごとのログイン状態自体はブロック2で作る)。
      MACアドレスはiOS/Androidともアプリから取得できない(プライバシー保護のため)。端末IDは
      初回起動時にUUIDを生成してsecure storageに保存するのが基本。貸与端末ならMDMの管理情報を
      使う選択肢もある

### 見送り

- OAuth(外部サービスでのログイン)、Firebase Auth/App Checkとの連携: 自前実装の後に比較する程度に留める
- QRコード読取(本案件寄りの機能)
- SNS的な拡張(bio・フォロー/フォロワー)

## 本案件の要件定義に持ち帰る観点

実装を通じて分かった制約は、orphanブランチ`tasks`の`requirement_takeaways.md`
(`/workspace/project/osampo-tracker/.claude/worktrees/task-management/requirement_takeaways.md`)に書き溜めている。
開発のブランチに関わらず1か所で見られるようにするため(2026-10-06にこのファイルから移した)。
