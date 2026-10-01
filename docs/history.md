# 変更履歴・経緯メモ

開発環境・運用ルールの変遷のうち、現在のルールの「なぜ」を説明するのに必要なもの。
機能の変更履歴はgitのログを参照。新しいものを上に追記する。

## 2026-10-01: CLAUDE.mdの分割

- 肥大化したCLAUDE.mdを、毎回読む必要があるもの(経緯・構成・テスト/git運用・守るべきルール)と、
  必要な時だけ読むもの(`docs/design/`・`docs/testing/`・`docs/pitfalls.md`・本ファイル・
  `docs/plans/`)に分けた
- コンテナ・POC運用に共通する内容(取り扱い禁止情報、MCP、
  バックグラウンドジョブの作業環境の注意)は`yoda-container/CLAUDE.md`に一本化した

## 2026-09-29: バックエンドをFastAPIに置き換える方針を決定

- 認証・メール送信を追加するにあたり、PostgRESTをやめてPython(FastAPI)のAPIサーバーに
  置き換える(DBはPostgreSQL/PostGISを継続)。詳細は`docs/plans/user-feature-plan.md`
- QR読取機能はこのアプリの用途に合わないので入れないと判断

## 2026-09-28: fvmの導入を取り止め、ホスト実行に一本化

- devcontainerにfvmでFlutterを入れ、ホストとバージョンを揃える案(`chore/fvm-flutter-version`)を
  試したが取り止めた。コンテナにはFlutter SDKを入れず、`flutter`/`dart`の実行は
  すべてホスト側で行う方針(`CLAUDE.md`の「開発環境の方針」)
- `frontend/.fvm/`はこの試行時の残骸(未追跡)。不要なのでホスト側で削除してよい
- 同時期に、ホスト実行の結果を`host_check_logs/`へファイルとして残す`scripts/run_checks.sh`を
  導入した。以前の`e2e_test_logs/`は旧形式のログ置き場で、今後は書き込まれない

## 2026-09-15〜09-28: 正規でないdevcontainer定義で作業していた期間

- 誤った入れ子の`.devcontainer`定義から起動していたため、firewall・named volumeが効いておらず、
  逆にdocker-in-dockerでコンテナ内でもDockerが使えていた(詳細:
  `yoda-container/docs/troubleshooting.md`の「正規のdevcontainer定義で起動しているかの確認」)
- **この期間に書かれた記述のうち、コンテナ側の環境に依存するもの(コンテナ内のFlutterのパス、
  Dockerの可否等)は正規コンテナでは当てはまらないことがある**。疑わしい記述を見つけたら
  正規コンテナで裏付けを取ってから更新すること
- `pubspec.lock`変更時のVSCodeの自動`pub get`によるホスト/コンテナ間の
  `package_config.json`取り合い(`docs/pitfalls.md`)はこの期間に発生した
