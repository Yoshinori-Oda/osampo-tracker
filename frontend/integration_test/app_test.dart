import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:test_tracking_01/main.dart' as app;

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
}
