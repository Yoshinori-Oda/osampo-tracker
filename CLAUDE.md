# 位置情報トラッキングアプリ (osampo-tracker)

Claude Code がこのプロジェクトで作業する際のコンテキスト。`yoda-container` の devcontainer 内、
`project/osampo-tracker` (このリポジトリ) で作業する。コンテナ自体の設定・POC運用ルールは
`yoda-container/CLAUDE.md` を参照。

## このプロジェクトの目的

次に配属される案件(以下「本案件」)のキャッチアップのため、技術面での実践演習として位置情報を利用したモバイルアプリの開発を行っている。

## キャッチアップの状況と方針 (重要)

2026-09-29時点の状況。機能の追加・取捨を提案する際はここを前提にすること。

- **経緯**: 2026-07末頃に開始(2026-09-29時点で約2ヶ月)。Flutter/Dartは未経験から学び始めた。
  最初の2週間でUdemy等を使って必須部分をさらい、以降はこのアプリをチャット型LLMと相談しながら
  写経と設計/実装修正(一部自力)を繰り返して現在の形になった
- **上長からの指示**: リポジトリ直下の`新人_Udemy受講指針メモ.md`(メインのチェックアウトにのみ
  ある未追跡ファイル)。ゴールは「地図に現在位置を出し、数秒おきに緯度経度をAPIへ送り、圏外時は
  ローカルに貯めて復帰後にまとめて送る」アプリを自力で作れること。優先順は
  Flutter/Dart入門 → 非同期(特にStream) → REST API連携(認証トークンの付与を含む) → 状態管理 →
  位置情報・地図 → ローカル保存/オフラインファースト。余力でQR読取(mobile_scanner)・FCM・Git
- **期限**: 本案件の開始は2026-10末前後の見込み。それまでの開発は2026-10-29を区切りとする
  (ロードマップ: `docs/roadmap.md`)
- **優先順位**: 本案件の要件定義に向けた知識(バックエンド・API設計・認証)を**リリースより優先する**。
  - 本案件は要件定義から始まるので、そこで効くのは「何を決めなければならないか」を手を動かして
    知っていること。リリースの知識が効くのはもっと後になる
  - 実装で分かった制約は`docs/user-feature-plan.md`の「本案件の要件定義に持ち帰る観点」に書き溜める
- **リリース**: 上長の指示ではない(ほぼ任されている状態)。自主的な目標で、納期は無い。意味は
  リリース作業を一通り体験することと、キャッチアップ期間の成果の保証。10月中はPlay Consoleの
  登録と内部テストトラックへのアップロードを試す程度に留め、アプリ側の仕上げ・公開は11月以降に
  個人で続ける。形態はリモート同期を使わずローカルのみで完結させ、個人名義ならAndroidのみで
  無料公開する想定。会社名義もあり得る(実績になるなら多少のコストは許容)。リリース作業は未経験で、
  詰まったら先輩社員にチャットで聞ける(月1の帰社日にまとめて相談することもできる)。
  作業の洗い出し: `docs/release-plan.md`
- **機能の取捨の方針**:
  - 本案件で求められる技術をすべてこのアプリに入れる必要はない。無理に入れるより、リリース時に
    一定の実用性がある機能だけに絞る
  - ただし、ユーザー機能・認証のように想定するリリース形態では不要でも、キャッチアップ上の価値が
    高いものは優先して取り組む(線引きと作業の洗い出し: `docs/user-feature-plan.md`)
  - 仕組みを理解することを重視する。認証基盤などは外部サービスに任せる前に、まず自前で実装する
- **本案件について分かっていること**(詳細設計は未定):
  - 機械にQRコードが貼ってあり、アプリで読み取ると、その機械と事前に割り当てられたタスクから
    ユーザーを割り出して(あるいはユーザー情報を持たずに)作業内容等を表示する「ワンストップ認証」が
    求められる
  - 使う認証サービス、通信の正当性の担保方法、端末の形態(個人/貸与、固定/流動)は未定で、
    本案件のスコープに含まれる
  - 管理者は必須。事前にタスクを作って機械ごとに割り振ったり、作業計画を作ったりする
  - DBはPostgreSQLを使う見込み(おそらくAmazon Aurora)
  - 本案件はゼロから要件定義を始める段階。開発まで受注できてもユーザーが開発に入るかは未定で、
    入るとしてもAI駆動開発になりそう。そのため、このアプリでのサーバー側・認証の実装は、実装経験を
    積むことより**要件定義に向けて制約(実装すべきこと/できないこと)を理解する**ことが主目的
  - QR読取機能はこのアプリの用途に合わないので入れない(2026-09-29判断)

## 技術スタック

- 言語: Dart
- フレームワーク: Flutter, Drift, Geolocator, flutter_map
- データベース: PostgreSQL (PostGIS) + PostgREST
  - 認証・メール送信を追加するにあたり、PostgRESTをやめてPython(FastAPI)のAPIサーバーに
    置き換える(2026-09-29決定。DBはPostgreSQL/PostGISを継続)。構成とパッケージは
    `docs/user-feature-plan.md`の「バックエンド構成」、日程は`docs/roadmap.md`を参照

## ディレクトリ構成
- tracking-app
    - backend
        Dockerで作るDBへ同期を行う。PostgreSQLのDBにPostgRESTでバックエンドAPIサーバーを構築
        - initdb.sql: スキーマ・ストアドファンクション(register_session_with_points / fetch_remote_sessions)の定義
        - cron/: 削除tombstoneの長周期パージ用cronコンテナ(Dockerfile / crontab / purge_deleted_sessions.sh)
        - docker-compose.yml: db / postgrest / cron の3サービス構成
    - docs
        - roadmap.md: 2026-10-29までのロードマップと、11月以降に回す作業
        - user-feature-plan.md: バックエンド構成・ユーザー機能・認証の検討内容と作業の洗い出し
        - release-plan.md: リリースに向けた論点と作業の洗い出し
    - frontend
        Flutterによるモバイルアプリの本体の開発を行う
        `flutter create`の出力から開発
        - lib: モバイルアプリ開発用ディレクトリ
            - database/: Drift定義(ローカルSQLite)
            - repositories/: リモート同期ロジック(push/pull/競合解決)
            - services/: 位置情報トラッキングのドメインロジック(tracking_service.dart。
              位置情報監視・収録の状態管理の中心。詳細は「位置情報取得の堅牢性設計」参照)と、
              location_stream_settings.dart(位置情報ストリームのプラットフォーム別設定。
              詳細は「バックグラウンド収録設計」参照)
            - models/: RecordingSession/Status/MoveMethodに加え、RecordingPhase
              (収録の状態遷移)、LocationBannerState/LocationBannerKind
              (位置情報バナーの状態)を持つ
            - providers/: Riverpodのprovider定義(recordingPhaseProvider/
              locationBannerProviderなど)
            - views/: 画面(例: saved_sessions.dartは保存済みセッション一覧。編集モード中に
              ListTileをタップすると名前・移動手段を編集するダイアログを表示する。名前欄は
              空欄でsubmitされた場合は変更しない。移動手段は`DropdownButtonFormField<MoveMethod>`
              で選択する。gps_help_page.dartはGPSを掴みやすくするためのTipsページ。
              save_or_discard_page.dartは収録停止後の保存/破棄画面で、session_detail_view.dartの
              `SessionDetailTitle`/`SessionDetailBody`を流用して詳細画面と同じ見た目にしている)
            - widgets/: 全タブ共通で表示するバナー(location_banner_view.dart/
              recording_phase_banner_view.dart)や、そこから使うgps_help_link.dartなど
            - utils/: navigatorKeyやダイアログ等、UI外から呼ぶための小物。
              save_or_discard_screen.dartは保存/破棄画面を表示する`showSaveOrDiscardScreen()`で、
              通常の停止/権限エラーによる強制停止/起動時リカバリのすべてから`TrackingService`経由で
              使う共通の入口(詳細は「起動時セッションリカバリ設計」の「保存/破棄画面」参照)。
              duration_format.dartは経過時間/時刻表示の共通フォーマッタ
        - Android: アンドロイド端末設定用ディレクトリ
        - iOS: iOS端末設定用ディレクトリ
        - integration_test/: `flutter drive`によるE2Eシナリオ(スクリーンショット取得含む)。
          詳細は「テスト」セクション参照
        - test_driver/: integration_test.dart(`flutter drive`実行時のドライバスクリプト。
          スクリーンショットをホストのファイルとして保存する役割)
        - scripts/: run_checks.sh(ホスト側で`flutter analyze`/`flutter test`/`flutter drive`等を
          実行し、結果をすべて`host_check_logs/`へ保存するスクリプト)と、そのe2eステップを呼ぶ
          だけのrun_e2e_tests.sh。詳細は「テスト」セクション参照

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
- **収録中に位置情報の権限/サービスが失われた場合**、`_forceStopForPermissionTrouble()`が
  `stopRecording(skipFinalPositionFetch: true)`を呼んで強制停止し、
  `utils/save_or_discard_screen.dart`の`showSaveOrDiscardScreen()`(通常の停止フローと
  共通化済み)を`navigatorKey`経由で呼び出して保存/破棄を確認する。**検知経路は
  `getPositionStream`の`onError`だけでは不十分**(実際に発生した不具合)。設定アプリでの
  権限/サービス変更は必ず一度アプリをバックグラウンドに回すため、多くの場合onErrorは
  発火しない。実質的な主検知経路は`main_page.dart`のフォアグラウンド復帰フックから呼ぶ
  `refreshLocationAvailability()`で、`RecordingPhase.recording`中にtroubleを検知した
  場合も同じ強制停止をトリガーする(`stopping`中の多重発火は`_phase`チェックで防止)。
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

## バックグラウンド収録設計 (重要)

収録中はアプリがバックグラウンドに回っても記録を継続し、収録していない間はバックグラウンドで
位置情報の購読を止める(サスペンドする)。別isolateのバックグラウンドserviceは使わず、
geolocatorの購読設定だけでプロセスを生かし続け、既存のDartコード(ストリームのlisten・
`Timer.periodic`・Driftへの書き込み)をそのまま動かす方式:

- **購読の開始/停止/設定の切り替えは`TrackingService._syncPositionStream()`に集約し、直列化している**。
  `_setPhase()`(フェーズ変化)と`handleAppLifecycleState()`(`main_page.dart`の
  `didChangeAppLifecycleState`から呼ぶ)の両方から呼ばれ、次の状態に合わせる:
  - `starting`/`recording`: バックグラウンド継続用の設定(`buildPositionStreamSettings(background: true)`)。
    Androidはgeolocatorの`ForegroundNotificationConfig`でForeground Service(常駐通知付き)を起動し、
    iOSは`allowBackgroundLocationUpdates: true`(Info.plistの`UIBackgroundModes`に`location`が必要)
  - `idle`/`stopping`: フォアグラウンド専用の設定。`hidden`/`paused`で購読と監視タイマーを止め、
    `resumed`で`refreshLocationAvailability()`経由で再開する。`inactive`は権限ダイアログや
    コントロールセンター表示中にも来るため購読を止めない
- **`starting`の時点でバックグラウンド用に切り替える**。Android 12以降はバックグラウンドから
  Foreground Serviceを起動できないため、RECを押した直後(確実にフォアグラウンドにいる時点)で
  起動しておく。バックグラウンドにいる間に購読が止まっている場合、フェーズ変化をきっかけに
  再購読はしない(`startIfStopped: false`)
- 権限は「使用中のみ許可」で足りる(フォアグラウンドで開始した更新はバックグラウンドでも継続できる)ため、
  Androidの`ACCESS_BACKGROUND_LOCATION`は要求しない(Play Consoleでの用途申告も不要)。Android 13以降の
  常駐通知の表示に必要な通知権限は、起動時に位置情報の権限の後で`permission_handler`で要求する
  (拒否されてもServiceは動く)
- iOSは`pauseLocationUpdatesAutomatically: false`にしている。trueだと静止中にOSが更新を止め、
  アプリがサスペンドされて`Timer.periodic`(5秒ごとのtrackpoint記録)も止まるため
- サスペンドからの復帰直後は、止めていた間の空白を「更新停止」バナーとして出さないよう、
  `_monitoringStartedAt`(監視を再開した時刻)を起点に10秒の猶予を置く。`startRecording()`の
  15秒フォールバック判定は従来通り実際の最終受信時刻(`_lastGoodPositionAt`)で行う
- 一部のAndroid端末(独自のバッテリー最適化を持つメーカー)は、Foreground Serviceでもプロセスごと
  終了させることがある。その場合は「起動時セッションリカバリ設計」の経路で保存/破棄させる
- 動作確認は実機、または位置の移動をシミュレートしたシミュレータ/エミュレータで行う
  (iOSシミュレータは`Features > Location > City Run`、Androidエミュレータは
  Extended controlsのRoutes)。収録中にホームへ戻り、数分後に復帰して軌跡が途切れていないかを見る

## 起動時セッションリカバリ設計 (重要)

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
  一方、1件だけのセッションは通常通り保存/破棄画面に乗せる(観光地で「ここに行った」という
  1点記録の用途があり得るため、意味のあるデータとして扱う)。
- **提示経路は3つ、すべて`resumePendingCompletion()`に集約する**:
  1. 収録タブの「収録開始」ボタンは`stopping`中「前回のセッションを処理」に差し替わり、
     タップで警告なしそのまま保存/破棄画面へ(アプリは常に収録タブから起動するため、実質
     これが既定の入口になる)
  2. 収録タブ以外にいる場合は、SnackBar(「収録画面へ」アクション付き)で誘導する
  3. `RecordingPhaseBannerView`の`stopping`表示(全タブ共通の常設バナー)もタップ可能にし、
     いつでも再度保存/破棄画面へ戻れるようにしてある(将来、起動時の既定タブを収録タブ以外に
     変更できるようにした場合に備えた導線。現状は常に収録タブから起動するため実質使われない)
  通常の停止フロー(`recording_page.dart`)も、停止後は`resumePendingCompletion()`で同じ画面を出す。
- **保存/破棄画面(`views/save_or_discard_page.dart`)の設計**:
  - 全画面ルート(`fullscreenDialog`)としてpushする。表示内容はセッション詳細画面を
    そのまま模したもの(セッション名は既定名、移動手段は未選択として空欄)で、強制停止/
    リカバリの理由(`infoMessage`)は下部固定領域の保存/破棄ボタンの上に赤文字で出す
  - 閉じる(×/戻る)は「後で決める」扱い。保存/破棄は未確定のまま`stopping`に残り、上記の
    提示経路からいつでも戻って来られる(収録タブ内に埋め込む案もあったが、どの画面からでも
    即戻れる点を優先してこの形にした)
  - 保存/破棄はどちらも確認ダイアログを挟む。破棄は「破棄/キャンセル」、保存は名前・移動手段を
    入力させるダイアログ(「保存/キャンセル」)。名前欄は既定名をヒント文字(`hintText`)で出し、
    空欄のまま保存したらその既定名で保存する。移動手段は`DropdownButtonFormField<MoveMethod>`
    で初期値は徒歩(将来オプションで「よく使う移動手段」を初期値にできるようにする想定)
  - 起動時リカバリのキューで次の1件がある場合は、開いている画面を`pushReplacement`で
    次のセッションの画面に差し替える。同じセッションの画面が既に開いていれば重ねて開かない
  - **`completeSession()`は保存/破棄のDB反映を待たずに、先に次の状態(次の1件の提示/idle)へ
    遷移する**。repository側の保存/破棄はリモート同期の完了まで待つため通信状況次第で時間が
    かかり、その間`stopping`のままだと確定済みのセッションの画面を再度開けてしまう(二重確定)
    ため。反映前にアプリが落ちても`inProgress`のまま残るだけで、次回起動時のリカバリで拾える。
    画面側はこの「呼び出しの中で同期的に差し替えが起きる」ことを前提に、自分がまだ
    `isCurrent`の場合だけpopしている

## 開発環境の方針 (コンテナ/ホストの役割分担) (重要)

- **devcontainerにはFlutter SDKを導入しない**(fvmでコンテナ内にFlutterを入れる案は
  2026-09-28に取り止めた)。コンテナ内では`flutter`/`dart`コマンドが使えない前提で作業すること。
  `flutter analyze`/`flutter test`/`dart run build_runner build`/`flutter drive`/ビルドは
  すべてホスト側で実行する
- **テストを軸に開発を進める**。Claudeはコンテナ内で実行による動作確認ができないため:
  - Claude: 実装と一緒に、その変更を検証するテスト(`test/`配下のユニット/ウィジェットテスト、
    画面確認が必要なら`integration_test/`のシナリオ)を書く。ホストで実行してもらう
    コマンドはコピペで実行できる完全な形で提示する
  - ユーザー: ホスト側で`scripts/run_checks.sh`を実行する(実行と完了報告のみ担当。
    結果はファイルに残るので、出力を貼り付けて渡す必要はない)
  - Claude: `frontend/host_check_logs/`の該当run_idの`SUMMARY.md`・各ログ・スクリーンショットを
    Readツールで読んで修正する(このディレクトリはbind mount経由でコンテナからも見える)。**実行結果を確認するまで
    「動作確認済み」とは言わない**
- Driftの`*.g.dart`などコード生成物もホスト側の`build_runner`でしか更新できない。
  テーブル定義を変えた場合は、生成コマンドの実行(`run_checks.sh <run_id> codegen ...`)を
  ユーザーに依頼すること
- 2026-09-15〜09-28のdevcontainerは、誤った入れ子の`.devcontainer`定義から起動していたため
  firewall・named volumeが効いていなかった(詳細: `yoda-container/docs/troubleshooting.md`の
  「正規のdevcontainer定義で起動しているかの確認」)。**この期間に書かれた本ファイルの
  記述のうち、コンテナ側の環境に依存するもの(コンテナ内のFlutterのパス、Dockerの可否等)は
  正規コンテナでは当てはまらないことがある**。疑わしい記述を見つけたら正規コンテナで
  裏付けを取ってから更新すること
- `frontend/.fvm/`はfvm試行時の残骸(未追跡)。不要なのでホスト側で削除してよい

## 開発ルール

### コーディング規約
- 現状はlinterは未導入
- Dartのインデントは2文字、SQLのインデントは4文字で行い、Dartではリスト項目の末尾にも`,`を入れる

### テスト
- 標準の`flutter_test`(`test/`配下、`flutter test`で実行)以外のテストフレームワーク・
  モックライブラリは未導入。テストは「開発環境の方針」の通りホスト側で実行する
- **ホスト側での実行はすべて`scripts/run_checks.sh <run_id> [step...]`で行う**(frontendで実行)。
  stepは`pubget`/`codegen`/`analyze`/`test`/`e2e`/`all`(=analyze test e2e)で、省略時は
  `analyze test`。指定順に関わらずpubget→codegen→analyze→test→e2eの順に1回ずつ実行し、
  途中で失敗しても残りのstepは実行する。`test`は`-t <path>`(複数可)で対象を絞れる
  (`test/widget_test.dart`は`flutter create`の雛形のまま壊れているため、全件実行すると
  これが失敗する。消すか直すまでは対象を明示すること)。`analyze`は`--no-fatal-infos`で
  実行するため既知のinfo(`avoid_print`)だけではFAILEDにならないが、指摘は全件記録する
- 結果は`frontend/host_check_logs/<timestamp>_<run_id>_<PASSED|FAILED>/`に保存される
  (`.gitignore`済み):
  - `SUMMARY.md`: 実行環境(ブランチ/コミット/未コミット変更の有無/ホストのFlutterバージョン)、
    stepごとの結果・終了コード・所要時間、analyzeの指摘一覧、testの失敗テスト名、
    失敗したstepのログ末尾。**Claudeはまずこれを読む**
  - `<step>.log`: 各stepの出力全文
  - `screenshots/`: e2eのスクリーンショットのコピー(実行ごとに残るので前回との比較にも使える)
- E2Eのみ実行する場合は従来通り`scripts/run_e2e_tests.sh <run_id>`でもよい(`run_checks.sh
  <run_id> e2e`を呼ぶだけのラッパー)。デバイスは省略可で、変える場合だけ
  `-d <device_id>`/`--device <device_id>`を足す。デバイスの決定順は`-d`指定 >
  `E2E_DEVICE_ID`環境変数 > `run_checks.sh`冒頭の`DEFAULT_DEVICE_ID`(各自の環境に
  合わせて書き換えておく)
- `run_id`はテスト内容の説明ではなく、**依頼ごとに変わる相関トークン**(Claudeがテスト実行を
  依頼する際にその場で生成し、コピペで実行できる完全なコマンドとして提示する)。複数セッションで
  テストが前後してもrun_idで検索すれば取り違えない。**同じrun_idを使い回して再実行すると
  どの実行結果か区別しにくくなるため、再実行を依頼する際も新しいrun_idを発行すること**。
  (以前の`e2e_test_logs/`は旧形式のログ置き場で、今後は書き込まれない)
- E2E/画面確認は`integration_test`パッケージ + `flutter drive`で行う。Claude Code は
  コンテナ内で動くためシミュレータ/実機を直接操作できず(そもそもコンテナにFlutterが
  無い)、次の役割分担で運用する:
  - ユーザー: ホスト側で`run_checks.sh <run_id> e2e`(または`run_e2e_tests.sh`)を実行して
    テストシナリオを走らせる(実行と完了報告のみ担当)
  - Claude: シナリオ(`integration_test/*.dart`)のコード自体は書く。実行後は該当run_idの
    `host_check_logs/.../screenshots/`(実行直後なら`frontend/integration_test_screenshots/`も
    同じ内容)のスクリーンショットPNGをReadツールで開いて解析する(bind mount経由で、
    ホストで生成したファイルがそのままコンテナから見える)
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
  - `integration_test`は(モックではなく)実機/シミュレータの本物の`app.sqlite`に対して
    動く。テスト用データを`AppDatabase`へ直接seedするシナリオで「保存」を伴う場合、
    `addTearDown`等で確実にそのセッションを後始末すること。忘れると実機の履歴データが
    汚染され、backendが生きている環境ではリモートDBにもpushされてしまう(詳細は
    「既知の落とし穴」参照)

### git
- **コード変更はgit worktree(`.claude/worktrees/<作業名>/`)で隔離して作業する**。ローカルmainが
  origin/mainより先行していることがあるので、`git worktree add .claude/worktrees/<作業名> -b <ブランチ名> main`
  でローカルmainから作り、`EnterWorktree(path=...)`で入る。手順・ホスト側のgit要件(2.48以上)・
  後片付けは`yoda-container/docs/worktree.md`を参照
- worktreeの作業結果はホスト側でそのworktreeのディレクトリを開いてテスト・ビルドする。
  worktreeごとに依存・生成物が別になるため、最初に`frontend`で`flutter pub get`(テーブル定義を
  変えた場合は`dart run build_runner build`も)を実行してもらう。backendの`docker compose`は
  ディレクトリ名から同じプロジェクト名(`backend`)になるので、メインのチェックアウトと
  worktreeで同時に起動しない
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
- backendはDockerが必須。**このdevcontainer環境ではDockerデーモンに繋がらない**
  (`docker`/`docker-compose`のCLIはあるが、`docker ps`が
  `dial unix /var/run/docker.sock: no such file or directory`で失敗する)ため、
  backendを起動できず、SQL変更は目視レビューに留まり実DBでの検証は常にホスト側に委ねる必要がある。
  (2026-09-16〜09-28は誤った入れ子のdevcontainer定義にdocker-in-dockerが入っていたため
  コンテナ内でもDockerが使えていたが、正規のcompose経由のコンテナでは使えない)
- iOSシミュレータの位置情報操作(Xcodeの`Features > Location`、`xcrun simctl location`)は
  macOSホスト専用の機能で、このLinuxコンテナには`xcrun`/`simctl`自体が存在せず実行できない。
  スクリプトやGPXファイルの作成はできるが、実行(位置の注入)は必ずホスト側で行うこと
- 同一テストプロセス内で`AppDatabase()`を複数回生成すると(`app.main()`実行後にseed用の
  `AppDatabase()`を追加で作る等)、Driftが
  `WARNING: It looks like you've created the database class AppDatabase multiple times`
  という警告を出す。debugビルドのみの警告で今のところテスト失敗には至っていないが、
  今後flakyになるようならテスト間でのDB接続の`close()`を検討すること
- `integration_test`の保存シナリオで後始末(`addTearDown`)を忘れ、実機の本物の履歴一覧に
  テスト用の偽セッションが残ってしまったことがある(実際に発生した不具合。残ってしまった
  場合はアプリの履歴タブの編集モードから手動で削除するしかない)。実DBへseedするテストを
  書くときは必ず「テストで作った行を確実に消す」経路(discardフロー経由 or 明示的な物理削除)
  を用意すること
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
- **Claude Codeがバックグラウンドジョブとして動作している場合、そのサンドボックスは
  上記のbind mount済みdevcontainerとは別の独立したgit cloneであることがある**(実際に
  発生: 作業ディレクトリが`docker-compose.yml`の`/workspace`と異なる`/workspaces/...`
  だった、他のバックグラウンドジョブとの競合でuncommittedな変更が消えた、等で判明)。
  ビルド関連の不具合調査でこの中のファイル(`.dart_tool`やXcodeの生成物など)を確認しても
  ユーザーの実機環境を反映しているとは限らないため、結論を出す前にユーザー自身の
  ホスト/devcontainer側で同じコマンドを実行してもらい、その出力で裏付けを取ること

## デバッグ Tips

- 同期の流れは`print`ベースのログ(`[sync] ...`)で追える。`avoid_print`のlint infoは既知で許容している
- 複数端末での同期テストは、同一の`_userId`(現状ハードコード: `11111111-1111-1111-1111-111111111111`)
  を共有する複数のシミュレータ/実機、または複数のローカルDBファイルで行う

## よく使うコマンド

backendの`docker compose`も含め、以下はすべてホスト側で実行する(コンテナにはFlutterが無い)。

```bash
# 起動
flutter run

# 以下はfrontendディレクトリで実行し、結果はhost_check_logs/<timestamp>_<run_id>_<結果>/に残る
# 静的解析 + ユニット/ウィジェットテスト(既定)
scripts/run_checks.sh <run_id>
# テスト対象を絞る
scripts/run_checks.sh <run_id> analyze test -t test/xxx_test.dart
# ローカルDB設定更新(build_runner)を含める / worktree作成直後はpubgetも
scripts/run_checks.sh <run_id> pubget codegen analyze test
# E2Eまで全部(ホスト側でシミュレータ/実機起動後に実行)
scripts/run_checks.sh <run_id> all
# E2Eのみ(デバイスを既定と変える場合のみ -d)
scripts/run_e2e_tests.sh <run_id> -d <device_id>

# backend起動(backendディレクトリで実行)
docker compose up -d
```

## 参考
