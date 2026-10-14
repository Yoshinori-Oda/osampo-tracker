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

String changePasswordErrorMessage(AuthException e) => switch (e.code) {
  'invalid_current_password' => '現在のパスワードが違います',
  'validation_error' => '新しいパスワードは8〜128文字にしてください',
  'unauthenticated' || 'token_expired' => 'ログインの有効期限が切れています。ログインし直してください',
  AuthException.network => 'サーバーに接続できませんでした。通信環境を確認してください',
  _ => 'パスワードを変更できませんでした(${e.code})',
};

String displayNameErrorMessage(AuthException e) => switch (e.code) {
  'validation_error' => '表示名は1〜50文字にしてください',
  'unauthenticated' || 'token_expired' => 'ログインの有効期限が切れています。ログインし直してください',
  AuthException.network => 'サーバーに接続できなかったため、変更できませんでした',
  _ => '表示名を変更できませんでした(${e.code})',
};

String verificationErrorMessage(AuthException e) => switch (e.code) {
  'invalid_verification_code' => 'コードが違います',
  'verification_code_expired' => '有効期限が切れたか、入力の回数の上限に達しました。コードを再発行してください',
  'too_many_requests' => '再発行には時間をあけてください',
  'unauthenticated' || 'token_expired' => 'ログインの有効期限が切れています。ログインし直してください',
  AuthException.network => '通信できませんでした',
  _ => '確認できませんでした(${e.code})',
};
