import '../../auth/auth_service.dart';

// APIのエラー(code)を画面に出すメッセージにする。codeの一覧はbackend/docs/API設計ドラフト.md

String loginErrorMessage(AuthException e) => switch (e.code) {
  'invalid_credentials' => 'メールアドレスまたはパスワードが違います',
  'account_disabled' => 'このアカウントは停止されています',
  AuthException.network => 'サーバーに接続できませんでした。通信環境を確認してください',
  _ => 'ログインできませんでした(${e.code})',
};

String signupErrorMessage(AuthException e) => switch (e.code) {
  'email_already_registered' => 'このメールアドレスは登録済みです。ログインしてください',
  'validation_error' => '入力内容を確認してください(メールアドレスの形式・パスワードの長さ)',
  AuthException.network => 'サーバーに接続できませんでした。通信環境を確認してください',
  _ => '登録できませんでした(${e.code})',
};
