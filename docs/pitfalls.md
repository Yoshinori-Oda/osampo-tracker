# 既知の落とし穴 (詳細)

`CLAUDE.md`の「既知の落とし穴」に要点だけ載せているものの、症状・原因・見分け方の詳細。
該当箇所を触る際や、似た症状の不具合を調べる際に読む。テストに関するものは
`docs/testing/e2e.md`、環境の変遷に関するものは`docs/history.md`を参照。

## 同期

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

## 地図 (flutter_map)

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

## レイアウト

- 画面上部に条件付きで出し入れするバナー(`main_page.dart`の収録状態/位置情報バナー等)を
  `SafeArea`で包む場合、`SafeArea`の`removeTop`は自分の子孫にしか伝播しない。
  バナーと兄弟関係にある別のWidget(タブ内の`AppBar`など)は、自分では
  まだステータスバー分のpaddingが消費されていないと判断して自前でも
  同じ分のpaddingを確保してしまい、バナー表示中だけ上部に二重の空白ができる。
  複数箇所で同じトップインセットを扱う場合は、`MediaQuery.removePadding`で
  明示的にどこまで消費済みにするかを揃えること(このアプリでの対処は
  `docs/design/location-tracking.md`のバナーの項を参照)

## ホスト/devcontainerの同時作業

- **`frontend`はdevcontainerとホストの両方からbind mountで同じファイルが見えるため、
  devcontainer側でVSCodeを開いたままにしていると、そのDart拡張が`pubspec.lock`等の
  変更をファイルウォッチャーで検知して自動で`flutter pub get`を実行してしまうことがある**
  (実際に発生した不具合)。ホストが書いた`.dart_tool/package_config.json`(正しいホスト
  パス`/Users/...`)が、devcontainer側のFlutterによってコンテナ内パス
  (`/home/node/flutter/...`)で上書きされ、ホストでのXcodeビルド中にこの上書きへ当たると
  `flutter`本体を含む外部パッケージが軒並み解決できなくなる(Xcodeのビルドログには
  "Missing package product"や大量の`isn't defined`エラーとして現れ、`flutter clean`や
  DerivedData削除を繰り返しても再現し続けるため原因が非常に分かりにくい)。
  `osampo-tracker`直下・`frontend`直下いずれの`.vscode/settings.json`にも
  `"dart.runPubGetOnPubspecChanges": "never"`を設定済みなので、devcontainer側/ホスト側
  どちらのVSCodeでも有効になっているか確認すること。原因切り分け時は、ホスト側で
  `grep -o '"rootUri": *"[^"]*flutter[^"]*"' .dart_tool/package_config.json`を実行し、
  `rootUri`がホストパスかコンテナパスかを見ると早い。
  (この不具合は誤った入れ子のdevcontainer定義で起動していた時期に、コンテナ内にFlutterが
  あった状態で発生した。現在はコンテナにFlutterを入れない方針なので同じ経路では再発しない
  はずだが、設定は念のため残しておく)
