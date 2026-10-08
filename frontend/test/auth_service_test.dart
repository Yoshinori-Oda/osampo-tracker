import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test_tracking_01/auth/auth_service.dart';
import 'package:test_tracking_01/auth/auth_storage.dart';
import 'package:test_tracking_01/auth/authorized_client.dart';
import 'package:test_tracking_01/database/app_database.dart';

// 認証(AuthService・AuthorizedClient)がbackend/docs/API設計ドラフト.mdの「認証のendpoints」を
// frontend/docs/ユーザー機能追加に伴う変更予定.mdの「認証(ブロック2)」の約束どおりに呼ぶことの確認

const _userId = '11111111-1111-1111-1111-111111111111';
const _baseUrl = 'http://test/api';
const _deviceId = '33333333-3333-3333-3333-333333333333';

class _MemoryAuthStorage implements AuthStorage {
  StoredAuth? stored;

  @override
  Future<String> deviceId() async => _deviceId;

  @override
  Future<StoredAuth?> read() async => stored;

  @override
  Future<void> save(StoredAuth auth) async => stored = auth;

  @override
  Future<void> clear() async => stored = null;
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(int status, String code) => _json(status, {'code': code, 'message': code});

Map<String, dynamic> _user({bool emailVerified = true}) => {
  'id': _userId,
  'email': 'test@example.com',
  'display_name': 'テスト',
  'email_verified': emailVerified,
  'role': 'user',
  'created_at': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> _tokens(String suffix, {bool emailVerified = true}) => {
  'access_token': 'access-$suffix',
  'refresh_token': 'refresh-$suffix',
  'token_type': 'Bearer',
  'expires_in': 900,
  'user': _user(emailVerified: emailVerified),
};

void main() {
  late AppDatabase db;
  late _MemoryAuthStorage storage;
  late List<http.Request> requests;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _MemoryAuthStorage();
    requests = [];
  });

  tearDown(() => db.close());

  AuthService createService(Future<http.Response> Function(http.Request request) handler) {
    final service = AuthService(
      db,
      storage,
      client: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
      baseUrl: _baseUrl,
    );
    addTearDown(service.dispose);
    return service;
  }

  Future<void> signIn(AuthService service) async {
    await db.upsertUser(id: _userId, email: 'test@example.com', displayName: 'テスト', emailVerified: true);
    storage.stored = const StoredAuth(userId: _userId, accessToken: 'access-0', refreshToken: 'refresh-0');
    await service.restore();
  }

  group('login・signup', () {
    test('ログインすると端末IDを付けて送り、ユーザーの行とトークンを保存する', () async {
      final service = createService((_) async => _json(200, _tokens('1', emailVerified: false)));

      final result = await service.login(email: 'test@example.com', password: 'password1');

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(requests.single.url.path, '/api/auth/login');
      expect(body, {'email': 'test@example.com', 'password': 'password1', 'device_id': _deviceId});
      expect(result.userId, _userId);
      expect(result.emailVerified, isFalse);
      expect(storage.stored!.accessToken, 'access-1');
      expect(service.userId, _userId);
      final user = (await db.getUser(_userId))!;
      expect(user.email, 'test@example.com');
      expect(user.emailVerified, isFalse);
    });

    test('新規登録で表示名が空なら送らない(サーバーがメールアドレスの@より前にする)', () async {
      final service = createService((_) async => _json(201, _tokens('1')));

      await service.signup(email: 'test@example.com', password: 'password1', displayName: '  ');

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(requests.single.url.path, '/api/auth/signup');
      expect(body.containsKey('display_name'), isFalse);
    });

    test('エラーはcodeをAuthExceptionにして投げ、何も保存しない', () async {
      final service = createService((_) async => _error(401, 'invalid_credentials'));

      await expectLater(
        service.login(email: 'test@example.com', password: 'wrong-password'),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'invalid_credentials')),
      );
      expect(storage.stored, isNull);
      expect(await db.getUser(_userId), isNull);
    });

    test('通信できなければnetworkのAuthExceptionを投げる', () async {
      final service = createService((_) async => throw http.ClientException('offline'));

      await expectLater(
        service.login(email: 'test@example.com', password: 'password1'),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', AuthException.network)),
      );
    });
  });

  group('refreshTokens', () {
    test('同時に呼ばれても通信は1回にまとめ、新しいトークンを保存する', () async {
      final completer = Completer<http.Response>();
      final service = createService((_) => completer.future);
      await signIn(service);

      final first = service.refreshTokens();
      final second = service.refreshTokens();
      completer.complete(_json(200, _tokens('2')));

      expect(await first, RefreshOutcome.refreshed);
      expect(await second, RefreshOutcome.refreshed);
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {'refresh_token': 'refresh-0'});
      expect(storage.stored!.refreshToken, 'refresh-2');
      expect(service.accessToken, 'access-2');
    });

    test('401はrejected(再ログインが必要)、通信できなければfailed(ログイン状態はそのまま)', () async {
      var response = _error(401, 'invalid_refresh_token');
      final service = createService((_) async => response);
      await signIn(service);

      expect(await service.refreshTokens(), RefreshOutcome.rejected);

      response = _error(503, 'service_unavailable');
      expect(await service.refreshTokens(), RefreshOutcome.failed);
      expect(storage.stored!.refreshToken, 'refresh-0');
    });
  });

  group('logout・deleteAccount', () {
    test('ログアウトはサーバーが失敗してもトークンを消し、ローカルのデータは残す', () async {
      final service = createService((_) async => throw http.ClientException('offline'));
      await signIn(service);

      await service.logout();

      expect(requests.single.url.path, '/api/auth/logout');
      expect(requests.single.headers['Authorization'], 'Bearer access-0');
      expect(storage.stored, isNull);
      expect(service.userId, isNull);
      expect(await db.getUser(_userId), isNotNull);
    });

    test('アカウントの削除に成功したら、そのユーザーのローカルのデータも消す', () async {
      final service = createService((_) async => http.Response('', 204));
      await signIn(service);
      final client = AuthorizedClient(service, inner: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }));

      await service.deleteAccount(client);

      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/api/users/me');
      expect(await db.getUser(_userId), isNull);
      expect(storage.stored, isNull);
    });

    test('アカウントの削除に失敗したら、何も消さずにAuthExceptionを投げる', () async {
      final service = createService((_) async => http.Response('', 204));
      await signIn(service);
      final client = AuthorizedClient(service, inner: MockClient((_) async => _error(500, 'internal_error')));

      await expectLater(
        service.deleteAccount(client),
        throwsA(isA<AuthException>().having((e) => e.code, 'code', 'internal_error')),
      );
      expect(await db.getUser(_userId), isNotNull);
      expect(storage.stored, isNotNull);
    });
  });

  group('AuthorizedClient', () {
    test('Bearerを付け、401(token_expired)ならトークンを更新して1回だけやり直す', () async {
      final service = createService((_) async => _json(200, _tokens('2')));
      await signIn(service);
      final apiRequests = <http.Request>[];
      final client = AuthorizedClient(service, inner: MockClient((request) async {
        apiRequests.add(request);
        return request.headers['Authorization'] == 'Bearer access-2'
          ? _json(200, {'ok': true})
          : _error(401, 'token_expired');
      }));

      final response = await client.post(Uri.parse('$_baseUrl/users/$_userId/sessions'), body: '{"id":"s1"}');

      expect(response.statusCode, 200);
      expect(apiRequests.map((r) => r.headers['Authorization']), ['Bearer access-0', 'Bearer access-2']);
      // やり直しでもbodyを同じに送る
      expect(apiRequests.last.body, '{"id":"s1"}');
      expect(requests.single.url.path, '/api/auth/refresh');
    });

    test('トークンの更新が拒否されたら、onAuthInvalidを呼んで401を返す', () async {
      final service = createService((_) async => _error(401, 'invalid_refresh_token'));
      await signIn(service);
      var invalidated = 0;
      final client = AuthorizedClient(
        service,
        inner: MockClient((_) async => _error(401, 'token_expired')),
        onAuthInvalid: () => invalidated++,
      );

      final response = await client.get(Uri.parse('$_baseUrl/users/me'));

      expect(response.statusCode, 401);
      expect(jsonDecode(response.body)['code'], 'token_expired');
      expect(invalidated, 1);
    });

    test('トークンの更新が通信できずに失敗したら、onAuthInvalidは呼ばない(次の機会に再び試す)', () async {
      final service = createService((_) async => throw http.ClientException('offline'));
      await signIn(service);
      var invalidated = 0;
      final client = AuthorizedClient(
        service,
        inner: MockClient((_) async => _error(401, 'token_expired')),
        onAuthInvalid: () => invalidated++,
      );

      final response = await client.get(Uri.parse('$_baseUrl/users/me'));

      expect(response.statusCode, 401);
      expect(invalidated, 0);
    });

    test('token_expired以外の401(ログアウト済み等)は更新せずにonAuthInvalidを呼ぶ', () async {
      final service = createService((_) async => _json(200, _tokens('2')));
      await signIn(service);
      var invalidated = 0;
      final client = AuthorizedClient(
        service,
        inner: MockClient((_) async => _error(401, 'unauthenticated')),
        onAuthInvalid: () => invalidated++,
      );

      final response = await client.get(Uri.parse('$_baseUrl/users/me'));

      expect(response.statusCode, 401);
      expect(invalidated, 1);
      expect(requests, isEmpty);
    });

    test('403(email_not_verified)ならonEmailNotVerifiedを呼び、レスポンスはそのまま返す', () async {
      final service = createService((_) async => _json(200, _tokens('2')));
      await signIn(service);
      var notVerified = 0;
      final client = AuthorizedClient(
        service,
        inner: MockClient((_) async => _error(403, 'email_not_verified')),
        onEmailNotVerified: () => notVerified++,
      );

      final response = await client.get(Uri.parse('$_baseUrl/users/$_userId/sessions'));

      expect(response.statusCode, 403);
      expect(jsonDecode(response.body)['code'], 'email_not_verified');
      expect(notVerified, 1);
    });
  });
}
