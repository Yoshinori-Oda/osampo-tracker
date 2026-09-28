---
paths:
  - "frontend/integration_test/**"
  - "frontend/test_driver/**"
  - "frontend/scripts/**"
  - "frontend/integration_test_screenshots/**"
  - "frontend/e2e_test_logs/**"
---

# E2Eテスト (integration_test + flutter drive)

## 実行方法

- E2E実行は`scripts/run_e2e_tests.sh <run_id>`(デバイスは省略可。変える場合だけ末尾に
  `-d <device_id>`/`--device <device_id>`を足す)で行う。デバイスの決定順は
  `-d`指定 > `E2E_DEVICE_ID`環境変数 > スクリプト冒頭の`DEFAULT_DEVICE_ID`(各自の環境に
  合わせて書き換えておく)
- `run_id`はテスト内容の説明ではなく、**依頼ごとに変わる相関トークン**(Claudeがテスト実行を
  依頼する際にその場で生成し、コピペで実行できる完全なコマンドとして提示する)。標準出力に
  流しつつ`e2e_test_logs/<timestamp>_<run_id>_<device_id>_<PASSED|FAILED>.log`にも保存するので、
  複数セッションでテストが前後してもrun_idで検索すれば取り違えない(`*.log`は`.gitignore`済み
  でコミット対象外)

## 役割分担

Claude Code はコンテナ内で動くためシミュレータ/実機を直接操作できず(`flutter devices`でも
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

## シナリオを書く際の注意

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
- `integration_test`は(モックではなく)実機/シミュレータの本物の`app.sqlite`に対して
  動く。テスト用データを`AppDatabase`へ直接seedするシナリオで「保存」を伴う場合、
  `addTearDown`等で確実にそのセッションを後始末すること。忘れると実機の履歴データが
  汚染され、backendが生きている環境ではリモートDBにもpushされてしまう

## 既知の落とし穴

- `integration_test`の保存シナリオで後始末(`addTearDown`)を忘れ、実機の本物の履歴一覧に
  テスト用の偽セッションが残ってしまったことがある(実際に発生した不具合。残ってしまった
  場合はアプリの履歴タブの編集モードから手動で削除するしかない)。実DBへseedするテストを
  書くときは必ず「テストで作った行を確実に消す」経路(discardフロー経由 or 明示的な物理削除)
  を用意すること
- 同一テストプロセス内で`AppDatabase()`を複数回生成すると(`app.main()`実行後にseed用の
  `AppDatabase()`を追加で作る等)、Driftが
  `WARNING: It looks like you've created the database class AppDatabase multiple times`
  という警告を出す。debugビルドのみの警告で今のところテスト失敗には至っていないが、
  今後flakyになるようならテスト間でのDB接続の`close()`を検討すること
