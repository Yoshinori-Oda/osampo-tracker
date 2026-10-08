import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database/app_database.dart';
import 'providers/auth_providers.dart';
import 'providers/tracking_providers.dart';
import 'views/auth/login_page.dart';
import 'views/main_page.dart';
import 'utils/delete_conflict_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db)
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Position Tracking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// 起動時の画面。ログイン状態を復元する間はスプラッシュ、未ログインならログイン画面、ログイン中ならメイン画面を出す。
// メイン画面はユーザーごとに作り直す(ユーザーIDをkeyにして、前のユーザーの画面の状態を引き継がない)
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.isLoading && !auth.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 復元に失敗した(端末の保存領域が読めない等)場合も、ログインし直してもらう
    final userId = auth.value?.userId;
    if (userId == null) return const LoginPage();
    return MainPage(key: ValueKey(userId));
  }
}