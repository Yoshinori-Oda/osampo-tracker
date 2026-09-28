# 位置情報トラッキングアプリ (osampo-tracker)

Claude Code がこのプロジェクトで作業する際のコンテキスト。`yoda-container` の devcontainer 内、
`project/osampo-tracker` (このリポジトリ) で作業する。コンテナ自体の設定・POC運用ルールは
`yoda-container/CLAUDE.md` を参照。

## このプロジェクトの目的

次に配属される案件のキャッチアップのため、技術面での実践演習として位置情報を利用したモバイルアプリの開発を行っている。

## 技術スタック

- 言語: Dart
- フレームワーク: Flutter, Drift, Geolocator, flutter_map
- データベース: PostgreSQL (PostGIS) + PostgREST

## 詳細ドキュメント (`.claude/rules/`)

設計の詳細・既知の落とし穴はトピックごとに`.claude/rules/`へ分割している。各ファイルは
`paths`フロントマターで対象ファイルを指定しており、該当ファイルを扱うと自動で読み込まれる。
**自動で読み込まれていなくても、下表のトピックに関わる作業・調査をする場合は着手前に該当
ファイルをReadすること。**

| ファイル | 内容 | 主な対象 |
|---|---|---|
| `sync-design.md` | 同期・削除の設計(tombstone/競合解決)、同期の落とし穴、同期のデバッグ | `repositories/`, `database/`, `backend/` |
| `location-tracking.md` | 位置情報取得の堅牢性設計(`RecordingPhase`/timeLimit/バナー/強制停止) | `services/`, `models/`, `providers/`, `widgets/`, `utils/`, `main_page.dart`, `recording_page.dart` |
| `session-recovery.md` | 起動時セッションリカバリ設計(`inProgress`残存セッションの保存/破棄) | `services/`, `database/`, `recording_page.dart` |
| `map-display.md` | `flutter_map`のグレー画面バグと回避策(`initialCameraFit`/`maxZoom`) | `views/`, `widgets/` |
| `e2e-testing.md` | E2Eテストの実行方法・役割分担・シナリオ作成時の注意 | `integration_test/`, `test_driver/`, `scripts/` |
| `dev-environment.md` | ホスト/devcontainer間のbind mount競合、バックグラウンドジョブの注意、FVM | `pubspec.*`, `.fvmrc`, `ios/`, `android/`, `.vscode/` |

## ディレクトリ構成
- tracking-app
    - backend
        Dockerで作るDBへ同期を行う。PostgreSQLのDBにPostgRESTでバックエンドAPIサーバーを構築
        - initdb.sql: スキーマ・ストアドファンクション(register_session_with_points / fetch_remote_sessions)の定義
        - cron/: 削除tombstoneの長周期パージ用cronコンテナ(Dockerfile / crontab / purge_deleted_sessions.sh)
        - docker-compose.yml: db / postgrest / cron の3サービス構成
    - frontend
        Flutterによるモバイルアプリの本体の開発を行う
        `flutter create`の出力から開発
        - lib: モバイルアプリ開発用ディレクトリ
            - database/: Drift定義(ローカルSQLite)
            - repositories/: リモート同期ロジック(push/pull/競合解決)
            - services/: 位置情報トラッキングのドメインロジック(tracking_service.dart。
              位置情報監視・収録の状態管理の中心)
            - models/: RecordingSession/Status/MoveMethodに加え、RecordingPhase
              (収録の状態遷移)、LocationBannerState/LocationBannerKind
              (位置情報バナーの状態)を持つ
            - providers/: Riverpodのprovider定義(recordingPhaseProvider/
              locationBannerProviderなど)
            - views/: 画面(例: saved_sessions.dartは保存済みセッション一覧。編集モード中に
              ListTileをタップすると名前・移動手段を編集するダイアログを表示する。名前欄は
              空欄でsubmitされた場合は変更しない。移動手段は`DropdownButtonFormField<MoveMethod>`
              で選択する。gps_help_page.dartはGPSを掴みやすくするためのTipsページ)
            - widgets/: 全タブ共通で表示するバナー(location_banner_view.dart/
              recording_phase_banner_view.dart)や、そこから使うgps_help_link.dartなど
            - utils/: navigatorKeyやダイアログ等、UI外から呼ぶための小物。
              save_or_discard_dialog.dartは収録停止後の保存/破棄ダイアログで、
              通常の停止フローと権限エラーによる強制停止フローの両方から使う共通部品。
              duration_format.dartは経過時間/時刻表示の共通フォーマッタ
        - Android: アンドロイド端末設定用ディレクトリ
        - iOS: iOS端末設定用ディレクトリ
        - integration_test/: `flutter drive`によるE2Eシナリオ(スクリーンショット取得含む)
        - test_driver/: integration_test.dart(`flutter drive`実行時のドライバスクリプト。
          スクリーンショットをホストのファイルとして保存する役割)
        - scripts/: run_e2e_tests.sh(`flutter drive`実行+ログ保存をまとめたラッパー)

## 開発ルール

### コーディング規約
- 現状はlinterは未導入
- Dartのインデントは2文字、SQLのインデントは4文字で行い、Dartではリスト項目の末尾にも`,`を入れる

### テスト
- ユニットテストのフレームワーク等は未導入
- E2E/画面確認は`integration_test` + `flutter drive`で行う。Claudeはシミュレータ/実機を
  操作できないため、**実行はユーザーがホスト側で行い、Claudeはシナリオの作成と
  スクリーンショットの解析を担当する**。実行を依頼する際はClaudeがその場で`run_id`を生成し、
  コピペで実行できる完全なコマンド(`scripts/run_e2e_tests.sh <run_id>`)として提示する
  (詳細: `.claude/rules/e2e-testing.md`)

### git
- commitメッセージはconventionalルールを継承する
- 1PR1目的を基本とし、無関係な変更を混在させない
- 現状は個人開発のため、レビュー承認は必須にしない(セルフマージ可)。複数人での開発に移行した場合はこのルールを見直す
- `frontend/pubspec.lock`はコミット対象(Flutterはアプリについてはlockをコミットするのが公式推奨。
  ライブラリ/プラグインとは扱いが異なるので注意)。`flutter analyze`等の実行で無関係な依存
  バージョンの差分が紛れ込むことがあるので、意図しない変更はコミット前に`git checkout`で戻す

### ドキュメント
- 新しい設計判断・既知の落とし穴を追記する際は、このファイルではなく該当する
  `.claude/rules/*.md`に書くこと。どれにも当てはまらないトピックが増えた場合は新しい
  ファイルを作り(`paths`フロントマターで対象を指定)、上の表に追加する。このファイルには
  常に必要な情報(目的・構成・開発ルール・環境の制約)だけを残す

## 重要な制約

このプロジェクトは Claude Code POC の対象である。以下を必ず守ること:

### 取り扱い禁止
- 本番 DB クレデンシャル
- 顧客個人情報
- 未公開財務情報
- 機微医療情報
- 第三者の著作物(契約上社内利用に限定されるもの)

### 設定の上書きについて
- 組織レベルの managed-settings(deny ルール等)は変更不可
- このプロジェクトの `.claude/settings.json` で個別の allow を追加可能
- 困ったら #claude-code-poc Slack チャンネルで質問

### MCP サーバ
- 許可された MCP サーバのみ使用可能(`/etc/claude-code/managed-mcp.json` 参照)
- このプロジェクトで使う MCP は `.mcp.json` に明示

## 実行環境の制約 (常に意識すること)

- **このdevcontainerではDockerデーモンに繋がらない**(`docker ps`が失敗する)ためbackendを
  起動できない。SQL変更は目視レビューに留まり、実DBでの検証はホスト側に委ねる
- **シミュレータ/実機・`xcrun`/`simctl`はコンテナから操作できない**。E2E実行や位置情報の
  注入はホスト側で行う
- **`frontend`はホストとdevcontainerでbind mount共有されている**。また、バックグラウンド
  ジョブのClaude Codeは独立したgit cloneで動いていることがある。ビルド不具合の調査では
  手元のファイルだけで結論を出さず、ユーザーの環境で裏付けを取ること
  (詳細: `.claude/rules/dev-environment.md`)
- devcontainer側のFlutterはFVM(`frontend/.fvmrc`)でホストのバージョンに追従させている
  (詳細: `.claude/rules/dev-environment.md`)

## よく使うコマンド

```bash
# 起動
flutter run

# ローカルDB設定更新(frontendディレクトリで実行)
dart run build_runner build

# 静的解析
flutter analyze

# E2Eテスト実行(ホスト側でシミュレータ/実機起動後に実行。frontendディレクトリで実行)
scripts/run_e2e_tests.sh <run_id>
# デバイスを既定(DEFAULT_DEVICE_ID/E2E_DEVICE_ID)と変える場合のみ
scripts/run_e2e_tests.sh <run_id> -d <device_id>

# backend起動(backendディレクトリで実行)
docker compose up -d
```
