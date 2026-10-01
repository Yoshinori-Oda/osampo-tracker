# E2E/画面確認テスト (integration_test + flutter drive)

`integration_test/`のシナリオを書く・直す際に読む。ホストでの実行方法とログの読み方は
`CLAUDE.md`の「テスト」を参照。

## 役割分担

Claude Code はコンテナ内で動くためシミュレータ/実機を直接操作できない(そもそもコンテナに
Flutterが無い)ため、次の役割分担で運用する:

- ユーザー: ホスト側で`scripts/run_checks.sh <run_id> e2e`(または`run_e2e_tests.sh`)を実行して
  テストシナリオを走らせる(実行と完了報告のみ担当)
- Claude: シナリオ(`integration_test/*.dart`)のコード自体は書く。実行後は該当run_idの
  `host_check_logs/.../screenshots/`(実行直後なら`frontend/integration_test_screenshots/`も
  同じ内容)のスクリーンショットPNGをReadツールで開いて解析する(bind mount経由で、
  ホストで生成したファイルがそのままコンテナから見える)

## スクリーンショットの仕組み

- `test_driver/integration_test.dart`が`onScreenshot`コールバックでPNGを
  `integration_test_screenshots/<name>.png`に書き出す。シナリオ側は
  `IntegrationTestWidgetsFlutterBinding.convertFlutterSurfaceToImage()`→
  `takeScreenshot('name')`の順で呼ぶ(Android実機/エミュレータでは
  `convertFlutterSurfaceToImage`が必須。iOSでは無視されるが呼んでおいて問題ない)
- `integration_test_screenshots/`は毎回上書きされる一時成果物なので`.gitignore`
  済み、コミット対象にしない

## 書き方の注意

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
- **`integration_test`は(モックではなく)実機/シミュレータの本物の`app.sqlite`に対して動く**。
  テスト用データを`AppDatabase`へ直接seedするシナリオで「保存」を伴う場合、
  `addTearDown`等で確実にそのセッションを後始末すること(discardフロー経由 or 明示的な物理削除)。
  忘れると実機の履歴データが汚染され、backendが生きている環境ではリモートDBにもpushされてしまう。
  実際に後始末を忘れて実機の履歴一覧にテスト用の偽セッションが残ったことがある(残ってしまった
  場合はアプリの履歴タブの編集モードから手動で削除するしかない)
- 同一テストプロセス内で`AppDatabase()`を複数回生成すると(`app.main()`実行後にseed用の
  `AppDatabase()`を追加で作る等)、Driftが
  `WARNING: It looks like you've created the database class AppDatabase multiple times`
  という警告を出す。debugビルドのみの警告で今のところテスト失敗には至っていないが、
  今後flakyになるようならテスト間でのDB接続の`close()`を検討すること

## 位置情報の注入

- iOSシミュレータの位置情報操作(Xcodeの`Features > Location`、`xcrun simctl location`)は
  macOSホスト専用の機能で、Linuxコンテナには`xcrun`/`simctl`自体が存在せず実行できない。
  スクリプトやGPXファイルの作成はできるが、実行(位置の注入)は必ずホスト側で行うこと
- Androidエミュレータは Extended controls の Routes で移動をシミュレートできる
