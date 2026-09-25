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
            - services/: 位置情報トラッキングのドメインロジック(tracking_service.dart。
              位置情報監視・収録の状態管理の中心。詳細は「位置情報取得の堅牢性設計」参照)
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
        - integration_test/: `flutter drive`によるE2Eシナリオ(スクリーンショット取得含む)。
          詳細は「テスト」セクション参照
        - test_driver/: integration_test.dart(`flutter drive`実行時のドライバスクリプト。
          スクリーンショットをホストのファイルとして保存する役割)

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

## 位置情報取得の堅牢性設計 (重要)

GPSが未確定/不正確な状態(アプリ起動直後・屋内・電波不良など)でも収録が壊れないよう、
`TrackingService`に位置情報監視の状態管理を持たせている。設計の要点:

- **収録の状態は`RecordingPhase`(idle/starting/recording/stopping)で管理する**。
  `startRecording()`はidleの時のみ受け付け、`starting`中は連打による二重start
  (レースコンディション)を防ぐガードになる。`recording_page.dart`は`starting`中、
  収録タブ全体を`AbsorbPointer`+オーバーレイでinactive化し、キャンセルボタンも出す。
- **`Geolocator.getCurrentPosition`は必ず`LocationSettings(timeLimit: ...)`を設定して
  呼ぶこと**(標準パラメータの`timeLimit`はdeprecated。`LocationSettings`経由で渡す)。
  無期限に待つと、GPS未確定のままハングし続ける。呼び出し箇所ごとにtimeLimitを変えている:
  `_initTrackingStream`の初回取得とstopRecordingは1秒、startRecordingは5秒
  (ストリームが既に動いていれば大抵は温まっているが、アプリ起動直後にすぐRECを
  押すケースは温まっていないため長めに取っている)。
- **`_lastGoodPositionAt`(DateTime?)が位置情報監視の中心的な状態**。精度に関わらず
  位置を受信するたびに更新し、これを起点に「未取得(null)」「更新停止(10秒以上経過)」
  を判定してバナー(`LocationBannerView`)に表示する。精度(accuracy>50m)は別軸の
  ヒステリシス付きカウンタ(+3/-1、無更新中は凍結、長時間の停止から復帰した際は
  クリーンに0リセット)で管理する。バナーの優先順位は権限エラー > 未取得/タイムアウト
  > 精度低下(1つだけ表示)。
- **`startRecording()`はOSの位置情報キャッシュ(`getLastKnownPosition()`)を使わない**。
  新鮮な位置が取れなければ、このセッション内で最後に確認できた位置
  (`_lastGoodPositionAt`が15秒以内)のみをフォールバック候補にし、確認ダイアログで
  開始可否を聞く。15秒を超える/一度も取得できていない場合は
  `StartRecordingBlockedException`を投げて開始をブロックする(再試行ボタン付きの
  エラーダイアログを表示)。「セッションとして意味のあるデータかどうか」を基準に
  しており、別セッション/別文脈の可能性があるOSキャッシュは意図的に除外している。
- **収録開始時のtrackpointの`recordedAt`は押下時刻ではなく`Position.timestamp`
  (実際にその位置情報が取得された時刻)を使う**。フォールバック開始時は数秒〜15秒
  古い時刻になり得るが、意図した挙動。
- **`stopRecording()`の終了地点取得もtimeLimit 1秒**。失敗した場合は最終ポイントの
  追加だけをスキップしてそのまま保存し、スナックバーで通知する。戻り値は`bool?`
  (null=取得を試みなかった、true=取得できた、false=取得を試みたが失敗した)。
- **収録中に位置情報の権限/サービスが失われた場合**(`getPositionStream`の`onError`で
  検知)、`_forceStopForPermissionTrouble()`が`stopRecording(skipFinalPositionFetch: true)`
  を呼んで強制停止し、`utils/save_or_discard_dialog.dart`の`showSaveOrDiscardDialog()`
  (通常の停止フローと共通化済み)を`navigatorKey`経由で呼び出して保存/破棄を確認する。
- **収録状態バナーと位置情報バナーは全タブ共通で`main_page.dart`の`body`上部に表示する**。
  どちらも非アクティブ時は`SizedBox.shrink()`で高さ0にする設計だが、それを包む
  padding/`SafeArea`は「バナーが1つもない時は一切描画しない」ようにしないと、
  ステータスバー避けの空白だけが常時残ってしまう。逆にバナー表示中は、タブ側
  (各`AppBar`)が自前でも同じ分のステータスバー避けpaddingを確保してしまい二重の
  空白になるため、`MediaQuery.removePadding(removeTop: hasAnyBanner)`でタブ側の
  重複分を明示的に消費している(詳細は`main_page.dart`参照)。
- GPSを掴みやすくするTipsは`views/gps_help_page.dart`にまとめ、「未取得/更新停止」の
  位置情報バナーと`startRecording`のブロックダイアログの両方から
  `widgets/gps_help_link.dart`経由でリンクしている。

## 開発ルール

### コーディング規約
- 現状はlinterは未導入
- Dartのインデントは2文字、SQLのインデントは4文字で行い、Dartではリスト項目の末尾にも`,`を入れる

### テスト
- ユニットテストのフレームワーク等は未導入
- E2E/画面確認は`integration_test`パッケージ + `flutter drive`で行う。Claude Code は
  コンテナ内で動くためシミュレータ/実機を直接操作できず(`flutter devices`でも
  Linux desktopしか見えない)、次の役割分担で運用する:
  - ユーザー: ホスト側で`flutter drive`を実行してテストシナリオを走らせる(実行と
    完了報告のみ担当)
  - Claude: シナリオ(`integration_test/*.dart`)のコード自体は書く。実行後は
    `frontend/integration_test_screenshots/`配下に保存されたスクリーンショットPNGを
    Readツールで開いて解析する(このディレクトリは`/workspace`にbind mountされて
    いるため、ホストで生成したファイルがそのままコンテナから見える)
  - `test_driver/integration_test.dart`が`onScreenshot`コールバックでPNGを
    `integration_test_screenshots/<name>.png`に書き出す。シナリオ側は
    `IntegrationTestWidgetsFlutterBinding.convertFlutterSurfaceToImage()`→
    `takeScreenshot('name')`の順で呼ぶ(Android実機/エミュレータでは
    `convertFlutterSurfaceToImage`が必須。iOSでは無視されるが呼んでおいて問題ない)
  - `integration_test_screenshots/`は毎回上書きされる一時成果物なので`.gitignore`
    済み、コミット対象にしない
  - **`pumpAndSettle()`は`flutter_map`のタイル読み込み(ネットワーク経由)の完了を待たない**
    (アニメーション/再描画フレームが収まるのを待つだけで、任意のFuture/HTTP完了は
    対象外のため)。地図が写るシーンでスクリーンショットを撮る前は、`pumpAndSettle()`に
    加えて`tester.pump(const Duration(seconds: 3))`等の実時間待機を挟むこと(実例:
    `integration_test/app_test.dart`)。挟まずに撮ると、タイルが揃う前の一部グレーの
    地図が写り込む
  - 上記の実時間待機を挟むと、`flutter drive`実行時に
    `VMServiceFlutterDriver: request_data message is taking a long time to complete...`
    という警告が出ることがあるが、これは想定通りの待機時間に対する定型の進捗ログであり、
    テスト失敗ではないので無視してよい

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
- 画面上部に条件付きで出し入れするバナー(`main_page.dart`の収録状態/位置情報バナー等)を
  `SafeArea`で包む場合、`SafeArea`の`removeTop`は自分の子孫にしか伝播しない。
  バナーと兄弟関係にある別のWidget(タブ内の`AppBar`など)は、自分では
  まだステータスバー分のpaddingが消費されていないと判断して自前でも
  同じ分のpaddingを確保してしまい、バナー表示中だけ上部に二重の空白ができる。
  複数箇所で同じトップインセットを扱う場合は、`MediaQuery.removePadding`で
  明示的にどこまで消費済みにするかを揃えること

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

# E2Eテスト実行(ホスト側でシミュレータ/実機起動後に実行。frontendディレクトリで実行)
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d <device_id>

# backend起動(backendディレクトリで実行)
docker compose up -d
```

## 参考
