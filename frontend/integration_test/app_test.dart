import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:test_tracking_01/database/app_database.dart';
import 'package:test_tracking_01/main.dart' as app;
import 'package:test_tracking_01/models/recording_session.dart';
import 'package:test_tracking_01/providers/tracking_providers.dart';

const _testUserId = '11111111-1111-1111-1111-111111111111';

// クラッシュ・強制終了で保存/破棄されないまま残った(status=inProgressの)セッションを
// 実DBへ直接再現する。同じsessionIdの残骸があれば先に消してから作るので再実行しても安全
Future<void> _seedOrphanedSession(
  AppDatabase db, {
  required String sessionId,
  required DateTime startedAt,
  int trackPointCount = 2,
}) async {
  final placeholder = RecordingSession(
    sessionId: sessionId,
    startedAt: startedAt,
    endedAt: null,
    totalDistance: 0,
    elapsedSeconds: 0,
    elevationGain: 0,
    maxAltitude: 0,
    minAltitude: 0,
  );
  await db.deleteRecordingSession(session: placeholder);
  await db.initSession(session: placeholder, userId: _testUserId);

  for (var i = 0; i < trackPointCount; i++) {
    await db.addTrackPoint(
      sessionId: sessionId,
      latitude: 35.681236 + i * 0.001,
      longitude: 139.767125 + i * 0.001,
      altitude: 10 + i.toDouble(),
      recordedAt: startedAt.add(Duration(seconds: i * 30))
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('起動して初期画面のスクリーンショットを撮る', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // flutter_mapのタイルはネットワーク経由で非同期に届くため、pumpAndSettle()では
    // 読み込み完了を待てない(Future/HTTPの完了はアニメーションフレームではないため)。
    // タイルが揃うまで実時間で待ってから撮る。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01_launch');
  });

  testWidgets('起動時に孤立したinProgressセッションを検出し保存/破棄ダイアログへ誘導する', (tester) async {
    const sessionId = 'e2e-orphan-recovery-session';
    final startedAt = DateTime.now().subtract(const Duration(minutes: 10));

    final db = AppDatabase();
    await _seedOrphanedSession(db, sessionId: sessionId, startedAt: startedAt);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const app.MyApp()
      )
    );
    await tester.pumpAndSettle();
    // recoverOrphanedSessions()はaddPostFrameCallback経由で呼ばれるため、確定するまで少し待つ
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 起動直後は収録タブを見ている状態なので、警告なしでそのまま保存/破棄ダイアログが出る
    expect(find.text('セッション保存'), findsOneWidget);
    expect(find.text('前回のセッションが意図せず中断されました。保存/破棄を選択してください。'), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02_orphan_recovery_dialog');

    // 名前欄は空欄のまま保存し、既定名になることを確認する
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('セッション保存'), findsNothing);
    expect(find.text('収録開始 (REC)'), findsOneWidget);

    // 履歴タブに保存されたことを確認する
    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    expect(find.textContaining('アクティビティ'), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03_orphan_recovery_saved_to_history');
  });

  testWidgets('複数の孤立セッションを1件ずつ保存/破棄させる(キュー処理)', (tester) async {
    const sessionId1 = 'e2e-orphan-queue-session-1';
    const sessionId2 = 'e2e-orphan-queue-session-2';
    final startedAt1 = DateTime.now().subtract(const Duration(minutes: 30));
    final startedAt2 = DateTime.now().subtract(const Duration(minutes: 20));

    final db = AppDatabase();
    await _seedOrphanedSession(db, sessionId: sessionId1, startedAt: startedAt1);
    await _seedOrphanedSession(db, sessionId: sessionId2, startedAt: startedAt2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const app.MyApp()
      )
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 1件目
    expect(find.text('セッション保存'), findsOneWidget);
    await tester.tap(find.text('破棄'));
    await tester.pumpAndSettle();

    // idleへ戻らず、キューの2件目がそのままstoppingとして続けて提示される
    expect(find.text('セッション保存'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04_orphan_queue_second_dialog');

    await tester.tap(find.text('破棄'));
    await tester.pumpAndSettle();

    // 全件解決後、通常の収録開始ボタンに戻る
    expect(find.text('セッション保存'), findsNothing);
    expect(find.text('収録開始 (REC)'), findsOneWidget);
  });

  testWidgets('trackpointが1件も無い孤立セッションはダイアログを出さず自動破棄する', (tester) async {
    const sessionId = 'e2e-orphan-empty-session';
    final startedAt = DateTime.now().subtract(const Duration(minutes: 5));

    final db = AppDatabase();
    await _seedOrphanedSession(db, sessionId: sessionId, startedAt: startedAt, trackPointCount: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const app.MyApp()
      )
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('セッション保存'), findsNothing);
    expect(find.text('収録開始 (REC)'), findsOneWidget);
  });
}
