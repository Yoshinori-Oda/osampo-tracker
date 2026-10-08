import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/app_database.dart';
import '../repositories/tracking_repository.dart';
import 'auth_storage.dart';

// APIが返したエラー(レスポンスbodyのcode)。画面で表示を分けるのに使う
class AuthException implements Exception {
  final String code;
  final int? statusCode;

  const AuthException(this.code, {this.statusCode});

  // 通信できなかった(圏外・タイムアウト・サーバーに届かない)
  static const network = 'network';

  @override
  String toString() => 'AuthException($code, $statusCode)';
}

// ログイン・新規登録の結果
class AuthResult {
  final String userId;
  final bool emailVerified;

  const AuthResult({required this.userId, required this.emailVerified});
}

enum RefreshOutcome {
  // 新しいトークンに更新できた
  refreshed,
  // サーバーが拒否した(invalid_refresh_token)。再ログインが必要
  rejected,
  // 通信できなかった。ログイン状態はそのまま(次の機会に再び試す)
  failed,
}

/// 認証(ログイン・新規登録・トークンの更新・ログアウト・アカウントの削除)。
/// サーバー側の仕様はbackend/docs/API設計ドラフト.mdの「認証のendpoints」、端末側の約束は
/// frontend/docs/ユーザー機能追加に伴う変更予定.mdの「認証(ブロック2)」
class AuthService {
  final AppDatabase _db;
  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;
  StoredAuth? _current;
  Future<RefreshOutcome>? _refreshing;

  static const Duration _timeoutDuration = Duration(seconds: 5);
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  AuthService(this._db, this._storage, {http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? TrackingRepository.defaultBaseUrl;

  String? get userId => _current?.userId;
  String? get accessToken => _current?.accessToken;

  /// 起動時に、保存してあるログイン状態を読み込む。ログイン中のユーザーIDを返す(未ログインならnull)
  Future<String?> restore() async {
    _current = await _storage.read();
    return _current?.userId;
  }

  Future<AuthResult> login({required String email, required String password}) {
    return _authenticate('/auth/login', {'email': email, 'password': password});
  }

  Future<AuthResult> signup({required String email, required String password, String? displayName}) {
    return _authenticate('/auth/signup', {
      'email': email,
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty) 'display_name': displayName.trim(),
    });
  }

  Future<AuthResult> _authenticate(String path, Map<String, dynamic> body) async {
    final payload = {...body, 'device_id': await _storage.deviceId()};
    final http.Response response;
    try {
      response = await _client
        .post(Uri.parse('$_baseUrl$path'), headers: _jsonHeaders, body: jsonEncode(payload))
        .timeout(_timeoutDuration);
    } catch (_) {
      throw const AuthException(AuthException.network);
    }
    if (response.statusCode ~/ 100 != 2) {
      throw AuthException(_errorCode(response) ?? 'unknown', statusCode: response.statusCode);
    }

    final tokens = json.decode(response.body) as Map<String, dynamic>;
    final user = tokens['user'] as Map<String, dynamic>;
    // sessions.user_idの外部キーのため、ユーザーの行を先に作ってからログイン状態を保存する
    await _db.upsertUser(
      id: user['id'] as String,
      email: user['email'] as String,
      displayName: user['display_name'] as String,
      emailVerified: user['email_verified'] as bool,
    );
    await _saveTokens(userId: user['id'] as String, tokens: tokens);
    return AuthResult(userId: user['id'] as String, emailVerified: user['email_verified'] as bool);
  }

  Future<void> _saveTokens({required String userId, required Map<String, dynamic> tokens}) async {
    final auth = StoredAuth(
      userId: userId,
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
    );
    await _storage.save(auth);
    _current = auth;
  }

  /// リフレッシュトークンでトークンを更新する。同時に複数回呼ばれても、通信は1回にまとめる
  /// (使用済みのリフレッシュトークンを再び送ると、サーバーがその端末のログイン状態を無効にしてしまうため)
  Future<RefreshOutcome> refreshTokens() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<RefreshOutcome> _refresh() async {
    final current = _current;
    if (current == null) return RefreshOutcome.rejected;
    final http.Response response;
    try {
      response = await _client
        .post(
          Uri.parse('$_baseUrl/auth/refresh'),
          headers: _jsonHeaders,
          body: jsonEncode({'refresh_token': current.refreshToken}),
        )
        .timeout(_timeoutDuration);
    } catch (_) {
      return RefreshOutcome.failed;
    }
    if (response.statusCode == 200) {
      await _saveTokens(userId: current.userId, tokens: json.decode(response.body) as Map<String, dynamic>);
      return RefreshOutcome.refreshed;
    }
    return response.statusCode == 401 ? RefreshOutcome.rejected : RefreshOutcome.failed;
  }

  /// サーバーの自分の情報(メールアドレスの確認状態など)を取り込む。取り込めたらtrue
  Future<bool> refreshProfile(http.Client authorizedClient) async {
    final current = _current;
    if (current == null) return false;
    try {
      final response = await authorizedClient
        .get(Uri.parse('$_baseUrl/users/me'), headers: {'Accept': 'application/json'})
        .timeout(_timeoutDuration);
      if (response.statusCode != 200) return false;
      final user = json.decode(response.body) as Map<String, dynamic>;
      await _db.upsertUser(
        id: current.userId,
        email: user['email'] as String,
        displayName: user['display_name'] as String,
        emailVerified: user['email_verified'] as bool,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ログアウトする。サーバーでその端末のログイン状態を無効にし(失敗しても続ける)、端末のトークンを消す。
  /// ローカルのデータはそのユーザーのものとして残す
  Future<void> logout() async {
    final current = _current;
    if (current != null) {
      try {
        await _client
          .post(Uri.parse('$_baseUrl/auth/logout'), headers: {'Authorization': 'Bearer ${current.accessToken}'})
          .timeout(_timeoutDuration);
      } catch (_) {
        // 圏外等でもログアウトは進める(サーバーのログイン状態は、リフレッシュトークンの期限切れで無効になる)
      }
    }
    await _storage.clear();
    _current = null;
  }

  /// アカウントを削除する(サーバーで物理削除し、成功したら端末のそのユーザーのデータも消す)
  Future<void> deleteAccount(http.Client authorizedClient) async {
    final current = _current;
    if (current == null) return;
    final http.Response response;
    try {
      response = await authorizedClient
        .delete(Uri.parse('$_baseUrl/users/me'))
        .timeout(_timeoutDuration);
    } catch (_) {
      throw const AuthException(AuthException.network);
    }
    if (response.statusCode != 204) {
      throw AuthException(_errorCode(response) ?? 'unknown', statusCode: response.statusCode);
    }
    await _db.deleteUserData(current.userId);
    await _storage.clear();
    _current = null;
  }

  String? _errorCode(http.Response response) {
    try {
      final body = json.decode(response.body);
      return body is Map<String, dynamic> ? body['code'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
