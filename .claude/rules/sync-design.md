---
paths:
  - "frontend/lib/repositories/**"
  - "frontend/lib/database/**"
  - "backend/**"
---

# 同期・削除の設計 (重要)

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
- backendはDockerが必須だが、このdevcontainer環境ではDockerデーモンに繋がらない
  (`docker ps`が`dial unix /var/run/docker.sock: no such file or directory`で失敗する)。
  SQL変更は目視レビューに留まり、実DBでの検証は常にホスト側に委ねること

## デバッグ Tips

- 同期の流れは`print`ベースのログ(`[sync] ...`)で追える。`avoid_print`のlint infoは既知で許容している
- 複数端末での同期テストは、同一の`_userId`(現状ハードコード: `11111111-1111-1111-1111-111111111111`)
  を共有する複数のシミュレータ/実機、または複数のローカルDBファイルで行う
