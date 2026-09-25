import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/app_database.dart';
import '../models/recording_session.dart';
import '../models/status.dart';
import '../models/move_method.dart';

// 削除されたセッションの猶予期間(リモートのtombstoneをこの期間残してから物理パージする)
const Duration _deletionRetention = Duration(days: 90);

enum PushOutcome { succeeded, retryableError, conflict }

class PushResult {
  final PushOutcome outcome;
  final Session? conflictSession;
  const PushResult(this.outcome, [this.conflictSession]);
}

// 他端末で削除されたセッションをローカルで編集していた場合の競合解決の選択肢
enum DeleteConflictChoice { discard, keep }

/// syncing service for remote PostgreSQL server and local Drift server
class TrackingRepository {
  final AppDatabase _db;
  final http.Client _client;
  final SharedPreferencesAsync _asyncPrefs = SharedPreferencesAsync();
  static const String _kLastSyncedAtKey = 'last_synced_at';
  final String _userId;
  final Future<DeleteConflictChoice> Function(Session session)? onDeleteConflict;
  Timer? _retryTimer;

  bool get isSchedulingRetry => _retryTimer != null;
  bool isSyncing = false;
  Future<String?> getLastSyncedAt() async {
    try {
      return await _asyncPrefs.getString(_kLastSyncedAtKey);
    } catch (e) {
      return null;
    }
  }

  TrackingRepository(this._db, this._userId, {http.Client? client, this.onDeleteConflict})
    : _client = client ?? http.Client() {
      // for test: delete last_synced_at every re-build
      _clearLastSyncedAtForTest();
    }
  
  void _clearLastSyncedAtForTest() {
    _asyncPrefs.remove(_kLastSyncedAtKey);
  }

  // API end point
  final String _baseUrl = 'http://localhost:3000';
  // short timeout duration
  static const Duration _timeoutDuration = Duration(seconds: 3);

  // ローカルの変更直後の同期依頼。中身はrequestSyncと同じ
  Future<void> onUpdateData() => requestSync();

  // make sync action if nothing waiting for sync, or wait for next time of every 5 min-activating timer
  Future<void> requestSync() async {
    if (isSchedulingRetry) return;
    if (isSyncing) {
      _startRetryTimer();
      return;
    }

    // try once and activate timer if not succeeded
    bool isSucceeded = await syncDiff();
    if (!isSucceeded) {
      _startRetryTimer();
    }
  }

  void _startRetryTimer() {
    if (_retryTimer != null) return;

    _retryTimer = Timer(const Duration(minutes: 5), () async {
      _retryTimer = null;
      final isSucceeded = await syncDiff();
      if (!isSucceeded) {
        _startRetryTimer();
      }
    });
  }

  void _stopReryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // sync action for first commitment of sessions and trackpoints
  // return bool of succeeded/failed to manage sync timer
  Future<bool> syncDiff() async {
    bool? isSucceeded;
    print('[sync] start syncing');
    try {
      isSyncing = true;
      final now = DateTime.now();

      // push all unsynced sessions
      final pushResult = await pushUnsyncedSessions(syncTime: now);
      print('[sync] push result: ${pushResult.outcome}');

      // 他端末で削除済みのセッションを編集していた場合はダイアログ等で解決してからpullへ進む
      if (pushResult.outcome == PushOutcome.conflict) {
        await _resolveDeleteConflict(pushResult.conflictSession!, syncTime: now);
      } else if (pushResult.outcome == PushOutcome.retryableError) {
        return false;
      }

      // pull remote data to local
      final isPullSucceeded = await fetchRemoteSessions(syncTime: now);
      print(isPullSucceeded ? '[sync] pull succeeded' : '[sync] pull failed');

      isSucceeded = isPullSucceeded;
    } on TimeoutException {
      // do nothing if timeouted
      print('[sync] sync failed by timeout');
    } on SocketException {
      // do nothing if no connection
      print('[sync] sync failed by socket');
    } catch (e) {
      // do nothing if error occured
      print('[sync] sync failed by $e');
    } finally {
      isSyncing = false;
      print('[sync] sync ended');
    }
    return isSucceeded ?? false;
  }

  // push all unsynced sessions
  // 500系エラー・削除競合はどちらも「これ以上このサイクルで通信を続けない」シグナルとしてcancel扱いにする
  Future<PushResult> pushUnsyncedSessions({required DateTime syncTime}) async {
    final unsyncedSessions = await _db.getUnsyncedSessions();

    for (final session in unsyncedSessions) {
      late http.Response response;
      if (session.status == Status.ended) {
        response = await registerSession(session: session, syncTime: syncTime);
      } else if (session.status == Status.updated) {
        response = await updateSession(session: session, syncTime: syncTime);
        if (response.statusCode ~/ 100 == 2 && _isEmptyRepresentation(response)) {
          // 対象がis_deleted済み(=他端末で削除済み)で更新が1件も当たらなかった
          return PushResult(PushOutcome.conflict, session);
        }
      } else if (session.status == Status.deletedUnsynced) {
        response = await pushSessionDeletion(session: session, syncTime: syncTime);
      } else {
        continue;
      }

      if (response.statusCode ~/ 100 == 2) {
        if (session.status == Status.deletedUnsynced) {
          await _db.finalizeSessionDeletion(sessionId: session.id);
        } else {
          await _db.markAsSynced(sessionId: session.id, syncTime: syncTime);
        }
      } else if (response.statusCode ~/ 100 == 5) {
        return const PushResult(PushOutcome.retryableError); // cancel all if server is not responsible
      } else {
        print(response.statusCode);
        return const PushResult(PushOutcome.retryableError);
      }
    }

    return const PushResult(PushOutcome.succeeded);
  }

  // 他端末での削除とローカルの未同期な変更が競合した際の解決
  Future<void> _resolveDeleteConflict(Session session, {required DateTime syncTime}) async {
    final choice = onDeleteConflict != null
      ? await onDeleteConflict!(session)
      : DeleteConflictChoice.discard;

    if (choice == DeleteConflictChoice.discard) {
      await _db.finalizeSessionDeletion(sessionId: session.id);
      return;
    }

    try {
      final response = await reviveSession(session: session, syncTime: syncTime);
      if (response.statusCode ~/ 100 == 2 && _isEmptyRepresentation(response)) {
        // 長周期パージで既に物理削除されていたので、初回登録として作り直す
        final registerResponse = await registerSession(session: session, syncTime: syncTime);
        if (registerResponse.statusCode ~/ 100 == 2) {
          await _db.markAsSynced(sessionId: session.id, syncTime: syncTime);
        }
      } else if (response.statusCode ~/ 100 == 2) {
        await _db.markAsSynced(sessionId: session.id, syncTime: syncTime);
      }
    } on TimeoutException {
    } on SocketException {}
  }

  bool _isEmptyRepresentation(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      return decoded is List && decoded.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> registerSession({required Session session, required DateTime syncTime}) async {
    // generate JSON payload
    final formattedSession = {
      'id': session.id,
      'user_id': session.userId,
      'name': session.name,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt?.toUtc().toIso8601String(),
      'is_favorite': session.isFavorite,
      'move_method': session.moveMethod.name,
      'total_distance': session.totalDistance,
      'duration_seconds': session.durationSeconds,
      'elevation_gain': session.elevationGain,
      'max_altitude': session.maxAltitude,
      'min_altitude': session.minAltitude,
      'updated_at': syncTime.toUtc().toIso8601String(),
    };
    
    // get TrackPoints for the session
    final trackPoints = await _db.getTrackPointsForSession(session.id);
    List<Map> formattedTrackPoints = [];
    if (trackPoints.isNotEmpty) {
      // bulk insert
      formattedTrackPoints = trackPoints.map((tp) {
        final String sessionId = tp.sessionId;
        final double lat = tp.latitude;
        final double lng = tp.longitude;
        final double? alt = tp.altitude;

        return {
          'session_id': sessionId,
          'latitude': lat,
          'longitude': lng,
          'altitude': alt,
          'recorded_at': tp.recordedAt.toUtc().toIso8601String(),
        };
      }).toList();
    }

    final payload = {
      'p_session': formattedSession,
      'p_track_points': formattedTrackPoints,
    };
    print(payload);

    // send HTTP POST request of Sessions
    final response = await _client.post(
          Uri.parse('$_baseUrl/rpc/register_session_with_points'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
      .timeout(_timeoutDuration);
    
    return response;
  }

  // 通常の更新。deleted_at=is.nullを条件に含めることで、他端末で削除済みの行を
  // 誤って上書きしないようにし、0件ヒットで削除競合を検出できるようにしている
  Future<http.Response> updateSession({required Session session, required DateTime syncTime}) async {
    final body = json.encode({
      'id': session.id,
      'name': session.name,
      'move_method': session.moveMethod.name,
      'is_favorite': session.isFavorite,
      'updated_at': syncTime.toUtc().toIso8601String(),
    });

    final response = await _client.patch(
      Uri.parse('$_baseUrl/sessions?id=eq.${session.id}&deleted_at=is.null'),
      headers: {
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: body
    )
    .timeout(_timeoutDuration);

    return response;
  }

  // 削除のpush。既に削除済み/パージ済みでも0件ヒットで構わない(目的の状態と一致するため)
  Future<http.Response> pushSessionDeletion({required Session session, required DateTime syncTime}) async {
    final body = json.encode({
      'deleted_at': syncTime.add(_deletionRetention).toUtc().toIso8601String(),
      'updated_at': syncTime.toUtc().toIso8601String(),
    });

    return await _client.patch(
      Uri.parse('$_baseUrl/sessions?id=eq.${session.id}'),
      headers: {'Content-Type': 'application/json'},
      body: body
    )
    .timeout(_timeoutDuration);
  }

  // 削除tombstoneの取り消し(蘇生)。deleted_atフィルタは付けず、idのみで対象を特定する
  Future<http.Response> reviveSession({required Session session, required DateTime syncTime}) async {
    final body = json.encode({
      'name': session.name,
      'move_method': session.moveMethod.name,
      'is_favorite': session.isFavorite,
      'deleted_at': null,
      'updated_at': syncTime.toUtc().toIso8601String(),
    });

    return await _client.patch(
      Uri.parse('$_baseUrl/sessions?id=eq.${session.id}'),
      headers: {
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: body
    )
    .timeout(_timeoutDuration);
  }

  // fetch data from remote DB
  Future<bool> fetchRemoteSessions({required DateTime syncTime}) async {
    // return value for 
    bool isSucceeded = true;
    final lastSyncedAt = await getLastSyncedAt();

    try {
      // construct query parameter
      final queryParams = <String,String>{
        'p_user_id': _userId,
        'p_sync_time': syncTime.toUtc().toIso8601String(),
      };
      if (lastSyncedAt != null) {
        queryParams['p_last_synced_at'] = lastSyncedAt;
      }
      final uri = Uri.parse('$_baseUrl/rpc/fetch_remote_sessions').replace(queryParameters: queryParams);

      final response = await _client.get(
            uri,
            headers: {'Accept': 'application/json'},
          )
        .timeout(_timeoutDuration);

      if (response.statusCode ~/ 100 == 2) {
        final List<dynamic> remoteSessions = json.decode(response.body);

        for (final item in remoteSessions) {
          final String sessionId = item['id'];

          // 他端末での削除tombstoneならローカルの行を物理削除して終わり
          if (item['deleted_at'] != null) {
            await _db.finalizeSessionDeletion(sessionId: sessionId);
            continue;
          }

          // register / update sessions / trackPoints
          // sessions setup
          final session = Session(
            id: sessionId,
            userId: item['user_id'],
            name: item['name'],
            startedAt: DateTime.parse(item['started_at']).toLocal(),
            endedAt: DateTime.parse(item['ended_at']).toLocal(),
            status: Status.synced,
            isFavorite: (item['is_favorite'] as bool),
            moveMethod: MoveMethod.values.byName(item['move_method'] as String),
            totalDistance: (item['total_distance'] as num).toDouble(),
            durationSeconds: (item['duration_seconds'] as num).toInt(),
            elevationGain: (item['elevation_gain'] as num).toDouble(),
            maxAltitude: (item['max_altitude'] as num?)?.toDouble(),
            minAltitude: (item['min_altitude'] as num?)?.toDouble(),
            updatedAt: syncTime,
          );

          // trackPoints setup
          final trackPoints = (item['track_points']
            .map<TrackPoint>((tpJson) => TrackPoint(
              id: 0,
              sessionId: sessionId,
              recordedAt: DateTime.parse(tpJson['recorded_at']).toLocal(),
              latitude: (tpJson['latitude'] as num).toDouble(),
              longitude: (tpJson['longitude'] as num).toDouble(),
              altitude: (tpJson['altitude'] as num?)?.toDouble(),
            ))
            ).toList();
          
          // register / update
          await _db.upsertByFetchedData(session: session, tps: trackPoints);
        }

        // update last_synced_at
        _asyncPrefs.setString(_kLastSyncedAtKey, syncTime.toUtc().toIso8601String());

      } else {
        print('[sync] pull failed by http status code ${response.statusCode}');
        print(response.body);
        isSucceeded = false;
      }
    } on TimeoutException {
      print('[sync] pull failed by timeout');
      isSucceeded = false;
    } on SocketException {
      print('[sync] pull failed by socket');
      isSucceeded = false;
    } catch (e, stackTrace) {
      print('pull failed by $e');
      print(stackTrace);
      isSucceeded = false;
    }

    return isSucceeded;
  }

  // for tracking service
  Future<int> initSession({
    required RecordingSession session,
  }) {
    return _db.initSession(session: session, userId: _userId);
  }

  Future<int> addTrackPoint({
    required String sessionId,
    required double latitude,
    required double longitude,
    required double altitude,
    required DateTime recordedAt,
  }) {
    return _db.addTrackPoint(
      sessionId: sessionId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      recordedAt: recordedAt,
    );
  }

  Future<void> saveCompletedSession({
    required RecordingSession session,
    required String name,
    required MoveMethod moveMethod,
    required DateTime savedAt,
  }) async {
    await _db.saveCompletedSession(
      session: session,
      name: name,
      moveMethod: moveMethod,
      savedAt: savedAt,
    );
    return await onUpdateData();
  }

  Future<void> deleteRecordingSession({
    required RecordingSession session,
  }) async {
    await _db.deleteRecordingSession(session: session);
    return await onUpdateData();
  }

  // 起動時リカバリ用: 孤立したinProgressセッションとそのtrackpoints
  Future<List<Session>> getInProgressSessions() => _db.getInProgressSessions();

  Future<List<TrackPoint>> getTrackPointsForSession(String sessionId) {
    return _db.getTrackPointsForSession(sessionId);
  }

  Future<void> deleteSession(Session session) async {
    await _db.deleteSession(session: session);
    return await onUpdateData();
  }

  Future<void> toggleFavorite(Session session) async {
    await _db.toggleFavorite(session);
    return await onUpdateData();
  }

  Future<void> updateSessionInfo({
    required Session session,
    required String sessionName,
    required MoveMethod moveMethod,
  }) async {
    await _db.updateSession(
      session: session,
      sessionName: sessionName,
      moveMethod: moveMethod,
      isFavorite: session.isFavorite,
    );
    return await onUpdateData();
  }

  void dispose() {
    _stopReryTimer();
    _client.close();
  }
}