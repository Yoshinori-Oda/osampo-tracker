import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/auth_service.dart';
import '../../providers/auth_providers.dart';
import '../../utils/app_log.dart';
import 'auth_error_messages.dart';
import 'signup_page.dart';

// ログイン画面。起動時に未ログインなら表示する(ローカルアカウントを作るまでの暫定で、ログインか新規登録をしないと先に進めない)。
// 再ログインのバナーから開いた場合(isRelogin)は、ログインしたら閉じて元の画面に戻る
class LoginPage extends ConsumerStatefulWidget {
  final bool isRelogin;

  const LoginPage({super.key, this.isRelogin = false});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      // ログイン状態が変わると起動時の画面(AuthGate)がメイン画面に切り替わるので、上に重ねた画面は閉じる
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      setState(() => _errorMessage = loginErrorMessage(e));
    } catch (e) {
      // 通信以外の失敗(端末の保存領域に書けない・レスポンスの形式が違う等)も、画面に出して止まらないようにする
      appLog('auth', 'unexpected error', error: e);
      if (mounted) setState(() => _errorMessage = '予期しないエラーが発生しました($e)');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isRelogin ? '再ログイン' : 'ログイン')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.isRelogin)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('ログイン状態が無効になったため、同期を止めています。ログインし直すと同期を再開します。'),
                  ),
                TextFormField(
                  key: const Key('login_email'),
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'メールアドレス'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'メールアドレスを入力してください' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login_password'),
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'パスワード'),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) => (value == null || value.isEmpty) ? 'パスワードを入力してください' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('login_submit'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ログイン'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupPage())),
                  child: const Text('アカウントを新規登録する'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
