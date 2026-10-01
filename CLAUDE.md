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
  実装で分かった制約は`docs/plans/user-feature-plan.md`の「本案件の要件定義に持ち帰る観点」に書き溜める
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
- データベース: PostgreSQL (PostGIS) + PostgREST
  - PostgRESTはPython(FastAPI)のAPIサーバーに置き換える予定(2026-09-29決定。DBは継続)。
    構成は`docs/plans/user-feature-plan.md`の「バックエンド構成」を参照

## ディレクトリ構成

- backend: Dockerで動かすPostgreSQL + PostgRESTのバックエンドAPI
  - initdb.sql: スキーマ・ストアドファンクション(register_session_with_points / fetch_remote_sessions)の定義
  - cron/: 削除tombstoneの長周期パージ用cronコンテナ
  - docker-compose.yml: db / postgrest / cron の3サービス構成
- docs: 設計・経緯・計画(下記「ドキュメント索引」)
- frontend: Flutterによるモバイルアプリ本体(`flutter create`の出力から開発)
  - lib/
    - database/: Drift定義(ローカルSQLite)
    - repositories/: リモート同期ロジック(push/pull/競合解決)
    - services/: tracking_service.dart(位置情報監視・収録の状態管理の中心)、
      location_stream_settings.dart(位置情報ストリームのプラットフォーム別設定)
    - models/: RecordingSession/Status/MoveMethod、RecordingPhase(収録の状態遷移)、
      LocationBannerState/LocationBannerKind(位置情報バナーの状態)
    - providers/: Riverpodのprovider定義
    - views/: 画面(main_page / recording_page / saved_sessions / session_detail_view /
      save_or_discard_page / gps_help_page など)
    - widgets/: 全タブ共通のバナー(location_banner_view / recording_phase_banner_view)など
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
| `docs/design/sync.md` | pull型差分同期、tombstone削除、削除と編集の競合 | `repositories/`・`backend/`を触る |
| `docs/design/location-tracking.md` | RecordingPhase、timeLimit、位置情報バナー、収録開始のフォールバック、権限喪失時の強制停止 | `tracking_service.dart`・バナー・`main_page`/`recording_page`を触る |
| `docs/design/background-recording.md` | バックグラウンドでの収録継続と非収録時の購読停止 | 位置情報の購読設定・ライフサイクル・権限・マニフェストを触る |
| `docs/design/session-recovery.md` | 起動時の未完了セッション回収、保存/破棄画面 | 収録停止〜保存/破棄の流れを触る |
| `docs/design/screens.md` | 各画面・バナー・utilsの個別仕様(編集ダイアログの挙動等) | `views/`・`widgets/`・`utils/`を触る |
| `docs/testing/e2e.md` | integration_testの書き方・スクリーンショット・実DBの後始末 | `integration_test/`を書く・直す |
| `docs/pitfalls.md` | 下記「既知の落とし穴」の症状・原因の詳細 | 該当箇所を触る、似た不具合を調べる |
| `docs/history.md` | 開発環境・運用ルールの変遷(fvm取り止め、正規でないdevcontainerの期間等) | 古い記述・ブランチの前提を疑う時 |
| `docs/plans/` | ロードマップ・ユーザー機能・リリース・本案件の検討メモ | 機能の追加・取捨や今後の計画を相談する |

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
  - ユーザー: ホスト側で`scripts/run_checks.sh`を実行する(実行と完了報告のみ担当。
    結果はファイルに残るので、出力を貼り付けて渡す必要はない)
  - Claude: `frontend/host_check_logs/`の該当run_idの`SUMMARY.md`・各ログ・スクリーンショットを
    Readツールで読んで修正する。**実行結果を確認するまで「動作確認済み」とは言わない**
- Driftの`*.g.dart`などコード生成物もホスト側の`build_runner`でしか更新できない。
  テーブル定義を変えた場合は`run_checks.sh <run_id> codegen ...`の実行をユーザーに依頼すること
- backendのSQL変更はコンテナ内では目視レビューに留まる。実DBでの検証はホスト側に依頼する

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

- 同期の比較に使うタイムスタンプ(`last_synced_at`等)は必ず`.toUtc().toIso8601String()`で保存・送信する
- `TrackingRepository`のコンストラクタは開発中、毎回`last_synced_at`をクリアする
  (`_clearLastSyncedAtForTest`)。本番相当の挙動を確認する場合は外す
- PostgRESTの更新PATCHで競合検出が必要なものには`&deleted_at=is.null`等のフィルタを必ず付ける
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

## デバッグ Tips

- 同期の流れは`print`ベースのログ(`[sync] ...`)で追える。`avoid_print`のlint infoは既知で許容している
- 複数端末での同期テストは、同一の`_userId`(現状ハードコード: `11111111-1111-1111-1111-111111111111`)
  を共有する複数のシミュレータ/実機、または複数のローカルDBファイルで行う

## よく使うコマンド

backendの`docker compose`も含め、以下はすべてホスト側で実行する(コンテナにはFlutterが無い)。

```bash
# 起動
flutter run

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

# backend起動(backendディレクトリで実行)
docker compose up -d
```
