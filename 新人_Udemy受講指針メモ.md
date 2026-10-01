# モバイル案件｜新人 事前学習メモ（Udemy 受講の指針）

**ゴール**：「地図に自分の現在位置を出し、数秒おきに緯度経度をAPIへ送り、圏外時はローカルに貯めて復帰後にまとめて送る」アプリを自力で作れる状態。
※Flutter採用は社内の想定であり確定ではないが、事前学習はFlutter前提で進めてよい。

## 優先順位（この順で取る）

1. **Flutter / Dart 入門（必須・最優先）**
   Dart文法、Widget、StatelessWidget と StatefulWidget、setState と再ビルド、画面遷移、pub.dev のパッケージ導入まで。
   → 検索ワード：`Flutter 入門`, `Flutter & Dart - The Complete Guide`

2. **非同期処理（必須・ここが最重要）**
   Future / async / await / **Stream**。位置情報はStreamで流れてきて、通信はFutureで返る。ここが曖昧だと以降が全部詰まる。入門講座に含まれていることが多いので、**Streamを扱っているか**を必ず目次で確認して選ぶ。

3. **REST API 連携（必須）**
   http または dio でのGET/POST、JSONのシリアライズ、ステータスコードとエラーハンドリング、認証トークンの付与。
   → 検索ワード：`Flutter REST API`, `Flutter HTTP JSON`

4. **状態管理（重要）**
   Riverpod または Provider をひとつ。setStateだけでは本案件の規模は破綻する。流派は問わないので1つ通しでやる。
   → 検索ワード：`Flutter Riverpod`, `Flutter 状態管理`

5. **位置情報と地図（本案件の中核）**
   geolocator での現在位置取得、**位置情報パーミッション**（iOS/Androidで作法が違う。「使用中のみ」と「常に許可」の差）、地図表示（flutter_map / MapLibre / Google Maps いずれか）、マーカーとポリゴンの描画。
   → 検索ワード：`Flutter Google Maps`, `Flutter geolocator`, `Flutter Map Location`
   ※単独講座が少ない領域。見つからなければ公式ドキュメントとパッケージREADMEで補う。

6. **ローカル保存とオフライン対応（本案件の中核）**
   SQLite / Drift / Isar のいずれかでの端末内保存。「まずローカルに書いて、後でサーバーに同期する」というオフラインファーストの考え方。
   → 検索ワード：`Flutter SQLite`, `Flutter local database`, `Flutter offline first`

7. **余力があれば**
   QRコード読取（mobile_scanner）、プッシュ通知（Firebase Cloud Messaging）、Git / GitHub の基本操作。

## 講座選びのチェックポイント

- **2024年以降の更新**があるもの（Flutterは変化が速く、古い講座はNull Safety前などで手が止まる）
- 「見て終わり」でなく**手を動かして1本アプリを完成させる**構成のもの
- 目次に **Stream / API通信 / 状態管理 / ローカルDB** が入っているか
- 日本語で不足する領域（地図・位置情報・オフライン同期）は**英語講座＋公式ドキュメント**も選択肢に入れる

## 想定ペース

1〜4 で2〜3週間、5〜6 で2週間程度。5・6 まで届かなくても、**1〜4 が固まっていれば案件に入れる**。
