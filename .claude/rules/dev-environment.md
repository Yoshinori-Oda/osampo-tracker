---
paths:
  - "frontend/pubspec.yaml"
  - "frontend/pubspec.lock"
  - "frontend/.fvmrc"
  - "frontend/.dart_tool/**"
  - "frontend/ios/**"
  - "frontend/android/**"
  - "**/.vscode/**"
---

# 開発環境 (ホスト/devcontainer間の共有・FVM)

ビルド不具合(Xcode/Gradleのビルド失敗、パッケージが解決できない等)を調査する際は、
該当ファイルを触らなくてもこのファイルを読むこと。

## 既知の落とし穴

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
  `rootUri`がホストパスかコンテナパスかを見ると早い
- **Claude Codeがバックグラウンドジョブとして動作している場合、そのサンドボックスは
  上記のbind mount済みdevcontainerとは別の独立したgit cloneであることがある**(実際に
  発生: 作業ディレクトリが`docker-compose.yml`の`/workspace`と異なる`/workspaces/...`
  だった、他のバックグラウンドジョブとの競合でuncommittedな変更が消えた、等で判明)。
  ビルド関連の不具合調査でこの中のファイル(`.dart_tool`やXcodeの生成物など)を確認しても
  ユーザーの実機環境を反映しているとは限らないため、結論を出す前にユーザー自身の
  ホスト/devcontainer側で同じコマンドを実行してもらい、その出力で裏付けを取ること

## Flutterバージョン管理 (FVM)

ホスト(実機テスト用)とdevcontainer(Claude Code/静的解析用)でFlutterのインストール方法が
無指定・別管理だったため、`pubspec.lock`が実行環境ごとに揺れたり、devcontainer側の
`flutter analyze`が実際とは違うSDKバージョンを見て赤線だらけになる不具合があった。現状は
1人・1台(ホスト)運用のため、**ホスト側の現在のバージョンを`frontend/.fvmrc`に固定し、
devcontainer側だけがFVM経由でそれに追従する**片側だけの構成にしている(ホスト側にFVM導入は
不要、今まで通りの運用でよい)。

- `frontend/.fvmrc`: ホストの`flutter --version`が変わったら追従してここも更新すること
  (自動検知はできないので、ホストをupgradeしたら手動で揃えてdevcontainerをrebuildする)
- devcontainerの`postCreateCommand`(rebuild時に一度だけ実行)が`.fvmrc`を読んで
  `fvm install`→`fvm flutter pub get`まで自動で行う。**ただしこれはVSCode/CursorのDev
  Containers拡張経由でのみ発火する**。CLIから`docker compose run --rm claude`で起動した
  場合は自動実行されないため、初回だけ手動で`cd frontend && fvm install && fvm flutter pub get`
  を実行すること
- devcontainer側でVSCodeの「Flutter SDKをダウンロード」的な標準インストールフローは
  二重管理になるため使わないこと(FVM管理下の`.fvm/flutter_sdk`をDart拡張が自動検出する)
