---
paths:
  - "frontend/lib/services/**"
  - "frontend/lib/database/**"
  - "frontend/lib/views/main_page.dart"
  - "frontend/lib/views/recording_page.dart"
  - "frontend/lib/widgets/recording_phase_banner_view.dart"
---

# 起動時セッションリカバリ設計 (重要)

アプリがクラッシュ・強制終了(OSによるバックグラウンドプロセスの回収を含む)すると、収録中
だったセッションは`Sessions.status = inProgress`のまま保存/破棄されずローカルDBへ残り続ける。
`watchAllSessions()`/`getUnsyncedSessions()`は`inProgress`を除外するため、何もしなければ
このセッションは一覧にも出ず同期もされず、見えないまま溜まり続ける。これを起動時に検出して
必ず保存/破棄させるための設計:

- **`RecordingPhase.stopping`を「保存/破棄が未確定」という状態として、通常の停止フローと
  起動時リカバリの両方で共用する**(新しいphase値は増やさない)。`TrackingService`が
  `_recoveryQueue`(未処理の`RecordingSession`のリスト)を持ち、`recoverOrphanedSessions()`
  が起動時に一度だけ`Status.inProgress`の行を全件取得してキューに積み、先頭の1件を
  `_session`にセットして`stopping`へ遷移させる。`completeSession()`で1件解決するたびに、
  キューが残っていればidleへ戻さず次の1件をそのまま`stopping`として提示し続ける
  (複数件同時発生は内部DB直書き換えでしか本来解消できないため、キューで1件ずつ処理させる
  設計にしている)。
- **集計値(距離/獲得標高/最高・最低高度/経過秒数)はライブ収録中`inProgress`のままではDBに
  反映されないため、リカバリ時は残っている`TrackPoints`から再計算する**
  (`_rebuildRecordingSessionFromTrackPoints`)。ライブ計算にあった精度フィルタ等は再現しない
  ため多少の誤差は許容している(トラックポイント表示がメインコンテンツで、集計値はおまけ
  という位置付けのため)。`elapsedSeconds`は`DateTime.now()`ではなく
  `max(0, 最後のtrackpointのrecordedAt - session.startedAt)`で計算すること(`recordedAt`は
  フォールバック開始時に`startedAt`より前になり得るため、クランプしないと負数になり得る)。
- **「復帰(resume)」は提供せず、保存/破棄のみを選ばせる**。クラッシュ〜再起動の空白時間は
  数秒〜数日と不定長になり得るため、`startRecording()`の15秒フォールバック判定よりもさらに
  弱い保証しか得られない。「その時その場にいた」という記録の意味を保証できない以上、続きは
  新しいセッションとして始めてもらう方針(`startRecording()`がOSキャッシュを意図的に
  除外しているのと同じ考え方)。
- **trackpointが1件も無い(初回書き込み前に落ちた)セッションは、保存/破棄を聞かず自動破棄する**。
  一方、1件だけのセッションは通常通りダイアログに乗せる(観光地で「ここに行った」という
  1点記録の用途があり得るため、意味のあるデータとして扱う)。
- **提示経路は3つ、すべて`resumePendingCompletion()`に集約する**:
  1. 収録タブの「収録開始」ボタンは`stopping`中「前回のセッションを処理」に差し替わり、
     タップで警告なしそのままダイアログへ(アプリは常に収録タブから起動するため、実質
     これが既定の入口になる)
  2. 収録タブ以外にいる場合は、SnackBar(「収録画面へ」アクション付き)で誘導する
  3. `RecordingPhaseBannerView`の`stopping`表示(全タブ共通の常設バナー)もタップ可能にし、
     いつでも再度ダイアログへ戻れるようにしてある(将来、起動時の既定タブを収録タブ以外に
     変更できるようにした場合に備えた導線。現状は常に収録タブから起動するため実質使われない)
