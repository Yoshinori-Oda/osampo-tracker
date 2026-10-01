# 画面・UI部品の仕様メモ

`frontend/lib/views/`・`widgets/`・`utils/`の個別の仕様。収録・保存/破棄の流れに関わるものは
`docs/design/location-tracking.md`・`docs/design/session-recovery.md`を参照。

## views/

- saved_sessions.dart: 保存済みセッション一覧。編集モード中にListTileをタップすると名前・移動手段を
  編集するダイアログを表示する。名前欄は空欄でsubmitされた場合は変更しない。移動手段は
  `DropdownButtonFormField<MoveMethod>`で選択する
- gps_help_page.dart: GPSを掴みやすくするためのTipsページ。「未取得/更新停止」の位置情報バナーと
  `startRecording`のブロックダイアログの両方から`widgets/gps_help_link.dart`経由でリンクしている
- save_or_discard_page.dart: 収録停止後の保存/破棄画面。session_detail_view.dartの
  `SessionDetailTitle`/`SessionDetailBody`を流用して詳細画面と同じ見た目にしている
  (詳細: `docs/design/session-recovery.md`の「保存/破棄画面」)

## widgets/

- location_banner_view.dart / recording_phase_banner_view.dart: 全タブ共通で`main_page.dart`の
  `body`上部に表示するバナー
- gps_help_link.dart: gps_help_pageへのリンク

## utils/

- save_or_discard_screen.dart: 保存/破棄画面を表示する`showSaveOrDiscardScreen()`。通常の停止/
  権限エラーによる強制停止/起動時リカバリのすべてから`TrackingService`経由で使う共通の入口
- duration_format.dart: 経過時間/時刻表示の共通フォーマッタ
