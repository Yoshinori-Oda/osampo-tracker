import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_service.dart';
import '../models/recording_phase.dart';
import '../providers/auth_providers.dart';
import '../providers/tracking_providers.dart';
import 'auth/email_verification_page.dart';

// 設定タブ。今はアカウント(表示・ログアウト・アカウントの削除)のみ。
// パスワードの変更はブロック3で追加する(メールアドレスの確認は、確認状態の行のタップで確認コードの入力画面を開く)
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;

  bool get _isRecording =>
    (ref.read(recordingPhaseProvider).value ?? RecordingPhase.idle) != RecordingPhase.idle;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ログアウトの前に未同期の変更を送っておく。失敗してもログアウトは進める
  // (未同期の記録はこの端末にそのユーザーのものとして残り、次にそのユーザーでログインした時に同期される)
  Future<void> _logout() async {
    if (_isRecording) {
      _showSnackBar('収録中はログアウトできません。収録を終了してから操作してください');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか?'),
        content: const Text('この端末の記録は残り、もう一度ログインすると表示されます。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ログアウト')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final synced = await ref.read(repositoryProvider).syncDiff();
    if (!mounted) return;
    if (!synced) {
      // ログアウトするとこの画面は消えるので、アプリ全体のSnackBarに出す
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('同期できなかった記録はこの端末に残り、次にログインした時に同期されます'),
      ));
    }
    // 次にログインしたユーザーの画面が収録タブから始まるようにする
    ref.read(bottomNavIndexProvider.notifier).setIndex(0);
    await ref.read(authControllerProvider.notifier).logout();
  }

  Future<void> _deleteAccount() async {
    if (_isRecording) {
      _showSnackBar('収録中はアカウントを削除できません。収録を終了してから操作してください');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除しますか?'),
        content: const Text('サーバーとこの端末から、このアカウントの記録が全て削除されます。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    // 削除に成功するとこの画面は消える(refが使えなくなる)ので、先に取っておく
    final bottomNav = ref.read(bottomNavIndexProvider.notifier);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      bottomNav.setIndex(0);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnackBar(switch (e.code) {
        AuthException.network => 'サーバーに接続できなかったため、削除できませんでした',
        'unauthenticated' || 'token_expired' => 'ログインし直してから、もう一度削除してください',
        _ => 'アカウントを削除できませんでした(${e.code})',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final auth = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const _SectionHeader('アカウント'),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(user?.displayName.isNotEmpty == true ? user!.displayName : '(表示名なし)'),
            subtitle: Text(user?.email ?? ''),
          ),
          ListTile(
            leading: Icon(auth?.emailVerified == true ? Icons.verified : Icons.mark_email_unread),
            title: Text(auth?.emailVerified == true ? 'メールアドレスは確認済みです' : 'メールアドレスが未確認です'),
            subtitle: auth?.emailVerified == true ? null : const Text('タップして確認コードを入力してください。確認が済むまで、記録はサーバーと同期されません'),
            // 未確認なら確認コードの入力画面を開く(収録中でも開ける。確認しても同期が始まるだけで収録の邪魔にならないため)
            onTap: auth?.emailVerified == true
              ? null
              : () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
                ),
          ),
          const Divider(),
          ListTile(
            key: const Key('settings_logout'),
            leading: const Icon(Icons.logout),
            title: const Text('ログアウト'),
            enabled: !_busy,
            onTap: _logout,
          ),
          ListTile(
            key: const Key('settings_delete_account'),
            leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            title: Text('アカウントを削除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            enabled: !_busy,
            onTap: _deleteAccount,
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
