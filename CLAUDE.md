# 位置情報トラッキングアプリ (osampo-tracker)

Claude Code がこのプロジェクトで作業する際のコンテキスト。`yoda-container` の devcontainer 内、
`project/osampo-tracker` (このリポジトリ) で作業する。コンテナ自体の設定・POC運用ルール
(取り扱い禁止情報・MCP・worktree運用等)は `yoda-container/CLAUDE.md` に書いてあり、
ここには書かない。

このファイルには毎回必要なことだけを書き、設計の詳細・経緯・計画は`docs/`に分けている
(下記「ドキュメント索引」)。追記する際も同じ基準で振り分けること。

## このプロジェクトの目的

次に配属される案件(以下「本案件」)のキャッチアップのため、技術面での実践演習として位置情報を利用したモバイルアプリの開発を行っている。

## キャッチアップの状況と方針 (重要)

2026-09-29時点の状況。機能の追加・取捨を提案する際はここを前提にすること。

- **経緯**: 2026-07末頃に開始。Flutter/Dartは未経験から学び始めた。最初の2週間でUdemy等を使って
  必須部分をさらい、以降はこのアプリをチャット型LLMと相談しながら写経と設計/実装修正(一部自力)を
  繰り返して現在の形になった
- **上長からの指示**: リポジトリ直下の`新人_Udemy受講指針メモ.md`(メインのチェックアウトにのみ
  ある未追跡ファイル)。ゴールは「地図に現在位置を出し、数秒おきに緯度経度をAPIへ送り、圏外時は
  ローカルに貯めて復帰後にまとめて送る」アプリを自力で作れること。優先順は
  Flutter/Dart入門 → 非同期(特にStream) → REST API連携(認証トークンの付与を含む) → 状態管理 →
  位置情報・地図 → ローカル保存/オフラインファースト。余力でQR読取(mobile_scanner)・FCM・Git
- **期限**: 本案件の開始は2026-10末前後の見込み。それまでの開発は2026-10-29を区切りとする
  (`docs/plans/roadmap.md`)
- **優先順位**: 本案件の要件定義に向けた知識(バックエンド・API設計・認証)を**リリースより優先する**。
  本案件は要件定義から始まるため、「何を決めなければならないか」を手を動かして知っていることが効く。
  実装で分かった制約はorphanブランチ`tasks`の`requirement_takeaways.md`に書き溜める(下記「タスク候補の管理」)
- **本案件**: QRコードによる「ワンストップ認証」・管理者によるタスク割り当てが求められ、DBは
  PostgreSQLの見込み。認証方式等は未定(詳細: `docs/plans/target-project.md`)
- **リリース**: 上長の指示ではない自主目標で納期は無い。リモート同期を使わずローカルのみで完結させる
  形態を想定し、10月中はPlay Consoleの登録と内部テストトラックへのアップロードを試す程度に留める
  (詳細: `docs/plans/release-plan.md`)
- **機能の取捨の方針**:
  - 本案件で求められる技術をすべてこのアプリに入れる必要はない。無理に入れるより、リリース時に
    一定の実用性がある機能だけに絞る
  - ただし、ユーザー機能・認証のように想定するリリース形態では不要でも、キャッチアップ上の価値が
    高いものは優先して取り組む(線引きと作業の洗い出し: `docs/plans/user-feature-plan.md`)
  - 仕組みを理解することを重視する。認証基盤などは外部サービスに任せる前に、まず自前で実装する

## 技術スタック

- 言語: Dart
- フレームワーク: Flutter, Drift, Geolocator, flutter_map, Riverpod
- バックエンド: PostgreSQL (PostGIS) + Python(FastAPI)のAPIサーバー
  - 2026-09-29にPostgRESTからの置き換えを決定し、2026-10-06にfrontendの同期を新しいAPIへ切り替えて
    PostgREST・cronを削除した。構成は`docs/plans/user-feature-plan.md`の「バックエンド構成」と
    `backend/docs/バックエンド構成.md`を参照

## ディレクトリ構成

- backend: Dockerで動かすバックエンド(FastAPIのapi + 定期実行のworker + PostgreSQL)
  - app/: FastAPIのアプリ本体(config.py: 設定、db.py: DB接続、main.py: アプリ、worker.py: 定期実行、
    security.py: パスワードのハッシュ・トークン、mail.py: SMTPでのメールの送信、cli.py: 管理用のコマンド(シード・アカウントの停止・テストメール)、
    routers/・schemas/・services/・models/: レイヤ。詳細は`backend/docs/バックエンド構成.md`)
  - tests/: pytest
  - pyproject.toml・uv.lock: 依存パッケージ(uv)。Dockerfile: api・worker共通のイメージ
  - alembic.ini・migrations/: Alembicのマイグレーション。0001は旧initdb.sqlのスキーマ(とPostgREST用のストアドファンクション)を
    そのまま写したもの、0002は高度関連の3列のdouble precision化、0003はPostgRESTの削除(ストアドファンクションの削除と
    deleted_atの「削除した日時」への統一)、0004は認証、0005はメールのoutbox、0006はメールアドレスの確認コード
  - db/init/: DBコンテナの初回起動時に実行するスクリプト(ロール・テスト用データベース・拡張機能・権限)
  - db/seed.sql: 開発用のダミーデータ(テストユーザー`1111...`とセッション)
  - docker-compose.yml: db / api / worker / mailpit。DBの接続情報は`backend/.env`(コミットしない)。
    メールはapiがoutboxに積み、workerがmailpitへ送る(届いたメールは http://localhost:8025 で見る)
  - docs/: FastAPIへの置き換えに向けたAPI設計・バックエンド構成の詳細設計(下記「ドキュメント索引」)
- docs: 設計・経緯・計画(下記「ドキュメント索引」)
- frontend: Flutterによるモバイルアプリ本体(`flutter create`の出力から開発)
  - docs/: ユーザー機能追加に伴うfrontendの変更予定(下記「ドキュメント索引」)
  - lib/
    - auth/: 認証(ログイン・トークンの更新・ログアウト・アカウントの削除)、トークンのsecure storageへの保存、
      アクセストークンを付けるHTTPクライアント(authorized_client.dart)
    - database/: Drift定義(ローカルSQLite)。ログインしたユーザー(users)ごとにデータを分ける
    - repositories/: リモート同期ロジック(push/pull/競合解決)
    - services/: tracking_service.dart(位置情報監視・収録の状態管理の中心)、
      location_stream_settings.dart(位置情報ストリームのプラットフォーム別設定)
    - models/: RecordingSession/Status/MoveMethod、RecordingPhase(収録の状態遷移)、
      LocationBannerState/LocationBannerKind(位置情報バナーの状態)
    - providers/: Riverpodのprovider定義
    - views/: 画面(main_page / recording_page / saved_sessions / session_detail_view /
      save_or_discard_page / gps_help_page / settings_page、auth/のログイン・新規登録 など)。
      起動時の画面は`main.dart`のAuthGate(未ログインならログイン画面)
    - widgets/: 全タブ共通のバナー(location_banner_view / recording_phase_banner_view /
      auth_banner_view)など
    - utils/: navigatorKeyやダイアログ等、UI外から呼ぶための小物。save_or_discard_screen.dartは
      保存/破棄画面を開く共通の入口`showSaveOrDiscardScreen()`
  - android/, ios/: 各OSの端末設定
  - test/: ユニット/ウィジェットテスト
  - integration_test/: `flutter drive`によるE2Eシナリオ(スクリーンショット取得含む)
  - test_driver/: `flutter drive`のドライバ(スクリーンショットをホストのファイルとして保存する)
  - scripts/: run_checks.sh(ホスト側で解析・テスト等を実行し結果を`host_check_logs/`へ保存)と、
    そのe2eステップだけを呼ぶrun_e2e_tests.sh

## ドキュメント索引

毎回読む必要はないが、**該当箇所を変更する前には必ずReadすること**。設計を変えたら同じ変更で
該当ドキュメントも更新する。

| ドキュメント | 内容 | 読むタイミング |
| --- | --- | --- |
| `docs/basic-design/` | 基本設計書(システム概要・機能一覧・画面一覧と遷移・データ設計・API一覧・認証とセキュリティ)。全体像と一覧に徹し、詳細は下記の各文書へリンクする | 全体像を掴む、機能・画面・テーブル・APIを追加/削除する(該当の一覧も更新する) |
| `docs/design/sync.md` | pull型差分同期、tombstone削除、削除と編集の競合 | `repositories/`・`backend/`を触る |
| `docs/design/location-tracking.md` | RecordingPhase、timeLimit、位置情報バナー、収録開始のフォールバック、権限喪失時の強制停止 | `tracking_service.dart`・バナー・`main_page`/`recording_page`を触る |
| `docs/design/background-recording.md` | バックグラウンドでの収録継続と非収録時の購読停止 | 位置情報の購読設定・ライフサイクル・権限・マニフェストを触る |
| `docs/design/session-recovery.md` | 起動時の未完了セッション回収、保存/破棄画面 | 収録停止〜保存/破棄の流れを触る |
| `docs/design/screens.md` | 各画面・バナー・utilsの個別仕様(編集ダイアログの挙動等) | `views/`・`widgets/`・`utils/`を触る |
| `docs/testing/e2e.md` | integration_testの書き方・スクリーンショット・実DBの後始末 | `integration_test/`を書く・直す |
| `docs/pitfalls.md` | 下記「既知の落とし穴」の症状・原因の詳細 | 該当箇所を触る、似た不具合を調べる |
| `docs/history.md` | 開発環境・運用ルールの変遷(fvm取り止め、正規でないdevcontainerの期間等) | 古い記述・ブランチの前提を疑う時 |
| `docs/plans/` | ロードマップ・ユーザー機能・リリース・本案件の検討メモ | 機能の追加・取捨や今後の計画を相談する |
| `backend/docs/API設計ドラフト.md` | 新しいAPIサーバー(FastAPI)のエンドポイント・エラー形式・認証と権限 | 新しいAPIを実装する、APIの仕様を変える |
| `backend/docs/バックエンド構成.md` | FastAPIへの置き換えの詳細設計(実装方針・マイグレーション・DBロール・パージ・テスト) | `backend/`の置き換え作業をする |
| `backend/docs/メール送信の運用.md` | メールをサーバーから送って運用するための論点(送信手段・到達性・バウンス・outbox・悪用対策・テスト)の整理 | メール送信の設計・実装をする、本案件のメール要件を考える |
| `frontend/docs/ユーザー機能追加に伴う変更予定.md` | 新しいAPIに合わせてfrontendで必要になる変更 | `repositories/`を新しいAPIに切り替える |

## タスク候補の管理

- 着手前のタスク候補は、orphanブランチ`tasks`の`task_candidates.md`に箇条書きで溜めている。`tasks`ブランチは
  専用のworktree`.claude/worktrees/task-management/`に常駐させ、**mainにはmergeせず、worktreeの後片付け
  (`git worktree remove`)の対象にもしない**(作業ブランチやworktreeによって内容が変わらないようにするため)
- 読むときは絶対パス`/workspace/project/osampo-tracker/.claude/worktrees/task-management/task_candidates.md`を使う
- 編集するときは、worktreeに隔離されたセッションでは`EnterWorktree(path=<上記worktreeのパス>)`で移ってから編集し、
  `tasks`ブランチにcommitする。元の作業に戻るときは`EnterWorktree(path=<作業中のworktreeのパス>)`で入り直す
- ユーザーに「次に何をやるか」を聞かれたら、このファイルを読み、上記「キャッチアップの状況と方針」の優先順位と
  `docs/plans/roadmap.md`の日程から優先度の高いものを選んで、理由を添えて提示する。判断できなければ一覧を提示する
- 作業中に見つかった後回しのタスク・ユーザーが挙げたタスクはこのファイルに追記し、完了したものは「完了」へ移す
- 同じ`tasks`ブランチの`requirement_takeaways.md`には、実装を通じて分かった「本案件の要件定義に持ち帰る観点」を
  テーマ別に書き溜める(タスクではないので`task_candidates.md`とは分ける)。編集の仕方は上と同じ
- worktreeが消えていた場合は`git worktree add .claude/worktrees/task-management tasks`で作り直す

## 開発環境の方針 (コンテナ/ホストの役割分担) (重要)

- **devcontainerにはFlutter SDKを導入しない**(fvmでコンテナ内にFlutterを入れる案は
  2026-09-28に取り止めた。経緯: `docs/history.md`)。コンテナはClaude Codeの隔離実行環境に徹し、
  解析・テスト・コード生成・ビルド・実機/シミュレータ操作はすべてホスト側で行う
- コンテナ内では次が使えない前提で作業する: `flutter`/`dart`、Dockerデーモン(`docker ps`は
  `/var/run/docker.sock`が無く失敗するためbackendを起動できない)、`xcrun`/`simctl`
  (iOSシミュレータの位置情報注入等はmacOSホスト専用)
- **テストを軸に開発を進める**。Claudeはコンテナ内で実行による動作確認ができないため:
  - Claude: 実装と一緒に、その変更を検証するテスト(`test/`配下のユニット/ウィジェットテスト、
    画面確認が必要なら`integration_test/`のシナリオ)を書き、ホストで実行してもらうコマンドを
    コピペで実行できる完全な形で提示する
  - ユーザー: ホスト側で`frontend/scripts/run_checks.sh`(backendは`backend/scripts/run_checks.sh`)を実行する
    (実行と完了報告のみ担当。結果はファイルに残るので、出力を貼り付けて渡す必要はない)
  - Claude: `frontend/host_check_logs/`(backendは`backend/host_check_logs/`)の該当run_idの`SUMMARY.md`・
    各ログ・スクリーンショットをReadツールで読んで修正する。**実行結果を確認するまで「動作確認済み」とは言わない**
- Driftの`*.g.dart`などコード生成物もホスト側の`build_runner`でしか更新できない。
  テーブル定義を変えた場合は`run_checks.sh <run_id> codegen ...`の実行をユーザーに依頼すること
- backendもDockerを使うのでコンテナ内では実行できない。SQL・マイグレーション・Pythonの変更はコンテナ内では目視レビューに
  留まり、実DBでの検証・テストはホスト側で`backend/scripts/run_checks.sh`を実行してもらう

## 開発ルール

### コーディング規約
- 現状はlinterは未導入
- Dartのインデントは2文字、SQLのインデントは4文字で行い、Dartではリスト項目の末尾にも`,`を入れる

### テスト
- 標準の`flutter_test`(`test/`配下)以外のテストフレームワーク・モックライブラリは未導入
- **ホスト側での実行はすべて`scripts/run_checks.sh <run_id> [step...]`で行う**(frontendで実行)。
  stepは`pubget`/`codegen`/`analyze`/`test`/`e2e`/`all`(=analyze test e2e)で、省略時は
  `analyze test`。指定順に関わらずpubget→codegen→analyze→test→e2eの順に1回ずつ実行し、
  途中で失敗しても残りのstepは実行する。`test`は`-t <path>`(複数可)で対象を絞れる
  (`test/widget_test.dart`は`flutter create`の雛形のまま壊れているため、全件実行すると
  これが失敗する。消すか直すまでは対象を明示すること)。`analyze`は`--no-fatal-infos`で
  実行するため既知のinfo(`avoid_print`)だけではFAILEDにならないが、指摘は全件記録する
- 結果は`frontend/host_check_logs/<timestamp>_<run_id>_<PASSED|FAILED>/`に保存される
  (`.gitignore`済み):
  - `SUMMARY.md`: 実行環境(ブランチ/コミット/未コミット変更の有無/ホストのFlutterバージョン)、
    stepごとの結果・終了コード・所要時間、analyzeの指摘一覧、testの失敗テスト名、
    失敗したstepのログ末尾。**Claudeはまずこれを読む**
  - `<step>.log`: 各stepの出力全文
  - `screenshots/`: e2eのスクリーンショットのコピー(実行ごとに残るので前回との比較にも使える)
- `run_id`はテスト内容の説明ではなく、**依頼ごとに変わる相関トークン**(Claudeがテスト実行を
  依頼する際にその場で生成し、コピペで実行できる完全なコマンドとして提示する)。**再実行を
  依頼する際も新しいrun_idを発行すること**(同じrun_idだとどの実行結果か区別しにくくなる)
- E2E/画面確認は`integration_test` + `flutter drive`で行う。E2Eだけなら
  `scripts/run_e2e_tests.sh <run_id>`でもよい(`run_checks.sh <run_id> e2e`のラッパー)。
  デバイスの決定順は`-d <device_id>` > `E2E_DEVICE_ID`環境変数 > `run_checks.sh`冒頭の
  `DEFAULT_DEVICE_ID`。シナリオの書き方は`docs/testing/e2e.md`
- `integration_test`は実機/シミュレータの本物の`app.sqlite`に対して動く。**seedして保存した
  セッションは必ず`addTearDown`等で後始末すること**(実機の履歴・リモートDBが汚染される)
- **backendのホスト側での実行は`backend/scripts/run_checks.sh <run_id> [step...]`で行う**(どこから実行してもよい)。
  frontend版と同じ形で、run_idの扱い・step順の固定・途中で失敗しても残りを実行するのも同じ。stepは
  `lock`(uv lock)/`up`(docker compose up -d --build)/`migrate`(開発用・テスト用DBへのalembic upgrade head)/`check`(alembic check)/`lint`(ruff check)/`test`(pytest。`-t`で絞れる)/`all`
  (=up migrate check lint test)で、省略時は`migrate check lint test`。
  - 依存パッケージを変えたら`lock up`、Dockerfile・compose・`pyproject.toml`・`alembic.ini`を変えたら`up`も付けて依頼する
    (`app/`・`tests/`・`migrations/`以外はbind mountしていないので、イメージの作り直しが必要)
  - 結果は`backend/host_check_logs/<timestamp>_<run_id>_<PASSED|FAILED>/`に保存される(`.gitignore`済み)。
    `SUMMARY.md`(実行環境、stepごとの結果、適用したマイグレーションとrevision、alembic checkの結果、ruffの指摘、
    pytestの失敗一覧と詳細、失敗したstepのログ末尾)をまず読む
  - 前提: `backend/.env`があり、`up`以外のstepはサービスが起動済みであること

### git
- **コード変更はgit worktree(`.claude/worktrees/<作業名>/`)で隔離して作業する**(手順は
  `yoda-container/CLAUDE.md`・`yoda-container/docs/worktree.md`)
- worktreeの作業結果はホスト側でそのworktreeのディレクトリを開いてテスト・ビルドする。
  worktreeごとに依存・生成物が別になるため、最初に`run_checks.sh <run_id> pubget`(テーブル定義を
  変えた場合は`codegen`も)を実行してもらう。backendの`docker compose`はディレクトリ名から
  同じプロジェクト名(`backend`)になるので、メインのチェックアウトとworktreeで同時に起動しない
- commitメッセージはconventionalルールを継承する
- 1PR1目的を基本とし、無関係な変更を混在させない
- 現状は個人開発のため、レビュー承認は必須にしない(セルフマージ可)。複数人での開発に移行した場合はこのルールを見直す
- `frontend/pubspec.lock`はコミット対象(Flutterはアプリについてはlockをコミットするのが公式推奨)。
  `flutter analyze`等の実行で無関係な依存バージョンの差分が紛れ込むことがあるので、
  意図しない変更はコミット前に`git checkout`で戻す

## 既知の落とし穴

守るべきルールの要点のみ。症状・原因・見分け方は`docs/pitfalls.md`を参照。

- `last_synced_at`はGETのレスポンスの`synced_at`をそのまま保存・送信する(端末で日時を組み立て直さない)
- `TrackingRepository`のコンストラクタは開発中、毎回`last_synced_at`をクリアする
  (`_clearLastSyncedAtForTest`)。本番相当の挙動を確認する場合は外す
- 同期APIの404は`code`が`session_not_found`のときだけ「サーバーにそのセッションが無い」として扱う
  (`code`の無い404・`user_not_found`では同期を止め、ローカルのデータに触れない)
- `TrackingRepository.updateSession()`はpush用の内部メソッド。ローカル編集用は`updateSessionInfo()`
  のように別名にする(同名だと`duplicate_definition`)
- `Geolocator.getCurrentPosition`は必ず`LocationSettings(timeLimit: ...)`付きで呼ぶ(無期限だとハングする)
- flutter_mapで初期表示時にboundsへフィットさせるときは、後から`fitCamera()`/`move()`を呼ばず
  `MapOptions.initialCameraFit`を使い、`CameraFit.bounds`には`maxZoom`を付ける(タイルがグレーのままになる)
- 上部に出し入れするバナーと`AppBar`の二重のステータスバー余白は`MediaQuery.removePadding`で揃える
- ホストとdevcontainerでVSCodeを同時に開く場合、`"dart.runPubGetOnPubspecChanges": "never"`が
  効いているか確認する(`.dart_tool/package_config.json`の取り合い)
- 2026-09-15〜09-28に書かれたコンテナ環境依存の記述は正規コンテナに当てはまらないことがある
  (`docs/history.md`)
- mainとworktreeの`backend`はcomposeのプロジェクト名(`backend`)・DBのボリュームを共有する。ユーザーの登録し直しは不要だが、
  古いコンテナが残ると`secrets/`のマウントが反映されずログインだけが500になる。おかしいときは`down`→`up`し直す
- シミュレータのアプリだけがAPIに繋がらない(タイムアウトし、APIのログにも届かない)ときは、Macの`127.0.0.1:8080`を
  Docker以外(VSCodeのプロセス等)が待ち受けていないか`lsof -nP -iTCP:8080 -sTCP:LISTEN`で確認する
  (`yoda-container/docs/troubleshooting.md`の「ホストのポートをVSCodeのプロセスが横取りする」)
- Driftのクエリで`&`・`|`を使うファイルでは`package:drift/drift.dart`をimportする。`flutter_secure_storage`は11系を使う
  (9系は`geolocator`とwin32が衝突する)

## デバッグ Tips

- 同期の流れは`print`ベースのログ(`[sync] ...`)で追える。`avoid_print`のlint infoは既知で許容している
- 複数端末での同期テストは、複数のシミュレータ/実機で同じユーザー(`app.cli seed-dev`のテストユーザー
  `testuser@example.com`等)にログインして行う。同期はメールアドレスが確認済みのユーザーでしか行われない

## よく使うコマンド

backendの`docker compose`も含め、以下はすべてホスト側で実行する(コンテナにはFlutterが無い)。

```bash
# 起動(同期先は既定でhttp://localhost:8080/api。実機・Androidエミュレータからはlocalhostに届かないので切り替える)
flutter run
flutter run --dart-define=API_BASE_URL=http://<ホストのIP>:8080/api

# 以下はfrontendディレクトリで実行し、結果はhost_check_logs/<timestamp>_<run_id>_<結果>/に残る
# 静的解析 + ユニット/ウィジェットテスト(既定)
scripts/run_checks.sh <run_id>
# テスト対象を絞る
scripts/run_checks.sh <run_id> analyze test -t test/xxx_test.dart
# ローカルDB設定更新(build_runner)を含める / worktree作成直後はpubgetも
scripts/run_checks.sh <run_id> pubget codegen analyze test
# E2Eまで全部(ホスト側でシミュレータ/実機起動後に実行)
scripts/run_checks.sh <run_id> all
# E2Eのみ(デバイスを既定と変える場合のみ -d)
scripts/run_e2e_tests.sh <run_id> -d <device_id>

# 以下はbackendディレクトリで実行し、結果はbackend/host_check_logs/<timestamp>_<run_id>_<結果>/に残る
# (事前にbackend/.envが必要: backend/docs/バックエンド構成.md)
# マイグレーション + スキーマの差分確認 + lint + テスト(既定。サービスは起動済みの前提)
scripts/run_checks.sh <run_id>
# 起動(イメージの作り直し)から全部
scripts/run_checks.sh <run_id> all
# 依存パッケージを変えた場合
scripts/run_checks.sh <run_id> lock up migrate check lint test
# テスト対象を絞る
scripts/run_checks.sh <run_id> test -t tests/test_models.py

# DBのボリュームを作り直した後は、マイグレーションの後に開発用のダミーデータを入れる(テーブルの所有者のロールで実行する)
docker compose down -v
scripts/run_checks.sh <run_id> up migrate
docker compose exec -T db psql -U osampo_migrator -d location_db < db/seed.sql
# 開発用のユーザー(管理者・テストユーザー1111...・メール未確認のユーザー)のパスワード等を設定する。ログイン情報が表示される
docker compose run --rm api python -m app.cli seed-dev

# アクセストークンを署名するES256の鍵のペアを作る(初回のみ。backend/secrets/はコミットしない)
mkdir -p secrets
openssl ecparam -name prime256v1 -genkey -noout -out secrets/jwt_private.pem
openssl ec -in secrets/jwt_private.pem -pubout -out secrets/jwt_public.pem
# アカウントの停止・解除(管理者の画面ができるまでの手段)
docker compose run --rm api python -m app.cli disable-user <email>
docker compose run --rm api python -m app.cli enable-user <email>
# テストメールをoutboxに積む(workerが数秒以内にmailpitへ送る。http://localhost:8025 で確認)
docker compose run --rm api python -m app.cli send-test-mail test@example.com
```
