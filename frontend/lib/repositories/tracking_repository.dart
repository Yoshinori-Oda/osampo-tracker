import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/app_database.dart';
import '../models/recording_session.dart';
import '../models/status.dart';
import '../models/move_method.dart';

/// syncing service for remote PostgreSQL server and local Drift server
class TrackingRepository {
  final AppDatabase _db;
  final http.Client _client;
  final SharedPreferencesAsync _asyncPrefs = SharedPreferencesAsync();
  static const String _kLastSyncedAtKey = 'last_synced_at';
  final String _userId;
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

  TrackingRepository(this._db, this._userId, [http.Client? client])
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

  // make sync action if nothing waiting for sync, or wait for next time of every 5 min-activating timer
  Future<void> onUpdateData() async {
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
      final isPushSucceeded = await pushUnsyncedSessions(syncTime: now);
      print(isPushSucceeded ? '[sync] push succeeded' : '[sync] push failed');

      // pull remote data to local
      final isPullSucceeded = await fetchRemoteSessions(syncTime: now);
      print(isPullSucceeded ? '[sync] pull succeeded' : '[sync] pull failed');

      isSucceeded = isPushSucceeded && isPullSucceeded;
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
  Future<bool> pushUnsyncedSessions({required DateTime syncTime}) async {
    bool isSucceeded = true;

    // list all of unsynced sessions
    final unsyncedSessions = await _db.getUnsyncedSessions();

    if (unsyncedSessions.isEmpty) return true;

    for (final session in unsyncedSessions) {
      late http.Response response;
      if (session.status == Status.ended) {
        response = await registerSession(session: session, syncTime: syncTime);
      } else if (session.status == Status.updated) {
        response = await updateSession(session: session, syncTime: syncTime);
      } else {
        continue;
      }

      // change syncStatus to 'synced' if succeeded
      if (response.statusCode ~/ 100 == 2) {
        await _db.markAsSynced(sessionId: session.id, syncTime: syncTime);
      } else if (response.statusCode ~/ 100 == 5) {
        isSucceeded = false;
        break; // cancel all if server is not responsible
      } else {
        isSucceeded = false;
        print(response.statusCode);
      }
    }

    return isSucceeded;
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

  Future<http.Response> updateSession({required Session session, required DateTime syncTime}) async {
    final body = json.encode({
      'id': session.id,
      'name': session.name,
      'move_method': session.moveMethod.name,
      'is_favorite': session.isFavorite,
      'updated_at': syncTime.toUtc().toIso8601String(),
    });

    final response = await _client.patch(
      Uri.parse('$_baseUrl/sessions?id=eq.${session.id}'),
      headers: {'Content-Type': 'application/json'},
      body: body
    )
    .timeout(_timeoutDuration);

    return response;
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
        _asyncPrefs.setString(_kLastSyncedAtKey, syncTime.toIso8601String());

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

  Future<void> toggleFavorite(Session session) async {
    await _db.toggleFavorite(session);
    return await onUpdateData();
  }

  void dispose() {
    _stopReryTimer();
    _client.close();
  }
}