import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';
import '../views/auth/login_page.dart';

// 同期が止まっている理由(再ログインが必要・メールアドレスが未確認)を、全タブ共通で上部に表示するバナー。
// 同期できる状態なら何も表示しない
class AuthBannerView extends ConsumerWidget {
  const AuthBannerView({super.key});

  // バナーを表示するか(MainPageの上部の余白の計算にも使う)
  static bool isActive(AuthState? auth) =>
    auth != null && auth.signedIn && (auth.needsRelogin || !auth.emailVerified);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).value;
    if (!isActive(auth)) return const SizedBox.shrink();

    final needsRelogin = auth!.needsRelogin;
    final message = needsRelogin
      ? 'ログインの有効期限が切れたため同期を止めています。タップしてログインし直してください'
      : 'メールアドレスが未確認のため、記録はサーバーと同期されません';

    return Material(
      color: needsRelogin ? Colors.orange.shade800 : Colors.blueGrey,
      child: InkWell(
        // メールアドレスの確認(コードの入力)はブロック3で追加する。今は再ログインのみタップで開く
        onTap: needsRelogin
          ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage(isRelogin: true)),
            )
          : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(needsRelogin ? Icons.lock_clock : Icons.mark_email_unread, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13))
              )
            ]
          )
        )
      )
    );
  }
}
