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
            - services/: 位置情報トラッキングのドメインロジック
            - providers/: Riverpodのprovider定義
            - views/: 画面(例: saved_sessions.dartは保存済みセッション一覧。編集モード中に
              ListTileをタップすると名前・移動手段を編集するダイアログを表示する。名前欄は
              空欄でsubmitされた場合は変更しない。移動手段は`DropdownButtonFormField<MoveMethod>`
              で選択する)
            - utils/: navigatorKeyやダイアログ等、UI外から呼ぶための小物
        - Android: アンドロイド端末設定用ディレクトリ
        - iOS: iOS端末設定用ディレクトリ

## 同期・削除の設計 (重要)

このアプリは「複数端末・同一ユーザーでの同時操作は想定しない」前提で、シンプルな
pull型差分同期(`updated_at`ベース)を採用している。設計の要点:

- **削除は物理削除ではなくtombstone方式**。`sessions.deleted_at`(削除確定から90日後の日時)を
  立てて`updated_at`も同時に更新することで、他端末が通常の差分pullの中で「削除された」ことを
  検知できるようにしている。ローカルのStatusにも`deletedUnsynced`があり、push成功が確認できた
  時点でローカル行はそのまま物理削除してよい(中間状態を残す必要はない、という結論に至った)。
- **リモートのtombstone行はcronで長周期パージ**する(`backend/cron/`、毎日3時に
  `deleted_at < now()`の行をDELETE)。他端末が確実にtombstoneを受け取れるよう、猶予期間
  (90日)を置いてから物理削除する。
- **削除と編集の競合**: 他端末で削除済み(`deleted_at`が入っている)セッションをローカルで編集
  していた場合、通常の更新PATCHは`deleted_at=is.null`を条件に含めているため0件ヒットになり、
  これを競合として検出する。検出時はダイアログで「削除を受け入れる/編集内容を残して復活させる
  (`deleted_at`をnullに戻すPATCH)」を選ばせる。復活先の行が長周期パージで既に物理削除されて
  いた場合は、`register_session_with_points`への初回登録として作り直すフォールバックがある。
- 同期のトリガーは「ローカルでの書き込み操作の直後」に加えて、通知offでも変更を取り込めるよう
  アプリ起動時・フォアグラウンド復帰時(`WidgetsBindingObserver`)にも呼んでいる。
- 本格的なリアルタイムpush(サーバー起動のpush通知等)は、複数端末同時操作を想定しない
  今回の規模では投資対効果が薄いと判断し採用していない。

## 開発ルール

### コーディング規約
- 現状はlinterは未導入
- Dartのインデントは2文字、SQLのインデントは4文字で行い、Dartではリスト項目の末尾にも`,`を入れる

### テスト
- 現時点ではテスト用のフレームワーク等は未導入

### git
- commitメッセージはconventionalルールを継承する
- 1PR1目的を基本とし、無関係な変更を混在させない
- 現状は個人開発のため、レビュー承認は必須にしない(セルフマージ可)。複数人での開発に移行した場合はこのルールを見直す
- `frontend/pubspec.lock`はコミット対象(Flutterはアプリについてはlockをコミットするのが公式推奨。
  ライブラリ/プラグインとは扱いが異なるので注意)。`flutter analyze`等の実行で無関係な依存
  バージョンの差分が紛れ込むことがあるので、意図しない変更はコミット前に`git checkout`で戻す

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

## 既知の落とし穴

- `last_synced_at`など同期の比較に使うタイムスタンプは必ず`.toUtc().toIso8601String()`で
  保存・送信すること。ローカル時刻のまま保存すると、UTC以外のタイムゾーンの端末で
  `p_last_synced_at`がタイムゾーン分だけ未来の値としてサーバーに解釈され、その間に他端末で
  更新された行がpullの差分から漏れ続ける不具合になる(実際に発生した既知の不具合)
- `TrackingRepository`のコンストラクタは開発中、毎回`last_synced_at`をクリアする
  (`_clearLastSyncedAtForTest`)。本番相当の挙動を確認したい場合はこれを外す必要がある
- PostgRESTのテーブル直叩きPATCHはidだけで絞ると`deleted_at`済みの行も無条件に上書きできて
  しまう。競合検出が必要な更新には`&deleted_at=is.null`等のフィルタを必ず付けること
- `TrackingRepository`には既にHTTP PATCH送信用の内部メソッド`updateSession()`が存在する
  (リモートへのpush用)。ローカルの名前・移動手段編集用ラッパーはこれと同名にすると
  `flutter analyze`で`duplicate_definition`エラーになるので、`updateSessionInfo()`のように
  別名にすること
- backendはDockerが必須(この開発環境ではDocker自体が使えない場合があるため、SQL変更は
  目視レビューに留まり実DBでの検証ができないことがある)
- `flutter_map`の`TileLayer`表示中に、`build()`内の`addPostFrameCallback`から
  `MapController.fitCamera()`/`move()`を呼んで後からズーム・中心を変更すると、
  `TileLayer`が最初の`initialZoom`向けにタイル読み込みを始めた後の状態遷移が
  うまく処理されず、タイルだけグレーのまま表示されなくなることがある(エラーは
  一切出ない。`PolylineLayer`/`MarkerLayer`は`MapCamera`を直接参照して毎フレーム
  描画するため正常に表示され、タイルだけ症状が出るのが見分け方)。初期表示時に
  boundsへ自動フィットしたい場合は、後から`fitCamera()`を呼ぶのではなく
  `MapOptions.initialCameraFit`を使うこと。`TileLayer`が一度も間違ったズームで
  タイル読み込みをする前に正しいカメラ状態で初期化されるため、この不具合が
  起きない(実例: `session_detail_view.dart`の`_DetailMapView`)
- セッションのトラックポイントは、REC開始から1秒以内(`TrackingService`の
  `Timer.periodic`が最初に発火する前)にSTOP→保存を確定すると1点だけになり得る
  (`elapsedSeconds`が`0`のままで、`stopRecording()`の終了点追加条件
  `% 5 != 0`を満たさないため)。トラックポイントが1点のみだと`LatLngBounds`の
  幅・高さが0になり、`CameraFit.bounds`のズーム計算が`Infinity`になって上記と
  同様のグレー画面バグを再現するため、`CameraFit.bounds`には`maxZoom`を
  設定してこの退化ケースを防ぐこと

## デバッグ Tips

- 同期の流れは`print`ベースのログ(`[sync] ...`)で追える。`avoid_print`のlint infoは既知で許容している
- 複数端末での同期テストは、同一の`_userId`(現状ハードコード: `11111111-1111-1111-1111-111111111111`)
  を共有する複数のシミュレータ/実機、または複数のローカルDBファイルで行う

## よく使うコマンド

```bash
# 起動
flutter run

# ローカルDB設定更新(frontendディレクトリで実行)
dart run build_runner build

# 静的解析
flutter analyze

# backend起動(backendディレクトリで実行)
docker compose up -d
```

## 参考
