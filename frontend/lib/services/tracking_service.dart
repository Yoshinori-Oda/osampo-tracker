import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../repositories/tracking_repository.dart';
import '../models/recording_session.dart';
import '../models/move_method.dart';
import '../models/location_banner.dart';
import '../utils/save_or_discard_dialog.dart';

// 端末/アプリ側の設定が原因で位置情報が取れなくなっている状態
enum _LocationPermissionTrouble { none, serviceDisabled, permissionDenied }

class TrackingService {
  // singleton services
  final TrackingRepository _repo;
  final _uuid = const Uuid();

  // 位置情報が「悪い精度」とみなすaccuracyのしきい値(メートル)
  static const double _poorAccuracyThresholdMeters = 50.0;
  // 更新が何秒途絶えたら「止まっている」とみなすか
  static const Duration _staleThreshold = Duration(seconds: 10);
  static const int _accuracyTroubleIncrement = 3;
  static const int _accuracyTroubleMax = 9;

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastPosition;

  RecordingSession? _session;
  Timer? _timer;
  Timer? _bannerWatchdogTimer;

  DateTime? _lastGoodPositionAt;
  int _accuracyTroubleCount = 0;
  _LocationPermissionTrouble _permissionTrouble = _LocationPermissionTrouble.none;

  // controllers to watch states (for Riverpod / UI)
  final _isRecordingController = StreamController<bool>.broadcast();
  final _currentPositionController = StreamController<Position>.broadcast();
  final _recordingSessionController = StreamController<RecordingSession?>.broadcast();
  final _locationBannerController = StreamController<LocationBannerState>.broadcast();

  // exported streams
  Stream<bool> get isRecordingStream => _isRecordingController.stream;
  Stream<Position> get currentPositionStream => _currentPositionController.stream;
  Stream<RecordingSession?> get recordingSessionStream => _recordingSessionController.stream;
  Stream<LocationBannerState> get locationBannerStream => _locationBannerController.stream;

  // startRecordingのフォールバック確認に使う、このセッションで最後に確認できた位置情報の受信時刻
  DateTime? get lastGoodPositionAt => _lastGoodPositionAt;

  // getters
  bool get isRecording => _session != null;
  RecordingSession? get recordingSession => _session;
  String? get currentSessionId => _session?.sessionId;
  double? get elevationGain => _session?.elevationGain;
  double? get maxAltitude => _session?.maxAltitude;
  double? get minAltitude => _session?.minAltitude;
  double? get avgSpeed => _session?.avgSpeed;

  TrackingService(this._repo) {
    _initTrackingStream();
  }

  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // track position
  Future<void> _initTrackingStream() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return;

    // get initial position (取れなくても以後はストリームからの更新を待つだけで良い)
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 1)
        )
      );
      _onPositionReceived(initialPosition);
    } catch (_) {}

    // get-location setting
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen(
      (Position position) async {
        _onPositionReceived(position);

        // 精度が悪い点はUI表示(現在地表示など)には使うが、
        // 距離・高度の積算(_onRecordingPositionUpdated)には使わない
        final isAccuracyOk = position.accuracy <= _poorAccuracyThresholdMeters;
        if (isRecording && _timer != null && isAccuracyOk) {
          await _onRecordingPositionUpdated(position);
        }
      },
      onError: _handleLocationStreamError
    );

    // 更新が来ていない間もバナーの表示/経過時間表示を追従させるための監視タイマー
    _bannerWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) => _recomputeBanner());
  }

  // 位置情報を(精度に関わらず)受信した際の共通処理
  void _onPositionReceived(Position position) {
    _currentPositionController.add(position);

    final wasStale = _lastGoodPositionAt == null ||
      DateTime.now().difference(_lastGoodPositionAt!) >= _staleThreshold;

    _lastGoodPositionAt = DateTime.now();
    _permissionTrouble = _LocationPermissionTrouble.none;

    // 長時間の停止から復帰した場合は、停止前の精度状態を引きずらずクリーンに再スタートする
    if (wasStale) {
      _accuracyTroubleCount = 0;
    }

    if (position.accuracy > _poorAccuracyThresholdMeters) {
      _accuracyTroubleCount = min(_accuracyTroubleCount + _accuracyTroubleIncrement, _accuracyTroubleMax);
    } else {
      _accuracyTroubleCount = max(_accuracyTroubleCount - 1, 0);
    }

    _recomputeBanner();
  }

  // 位置情報サービスOFF・権限剥奪などストリーム側のエラー
  void _handleLocationStreamError(Object error) {
    if (error is LocationServiceDisabledException) {
      _permissionTrouble = _LocationPermissionTrouble.serviceDisabled;
    } else if (error is PermissionDeniedException) {
      _permissionTrouble = _LocationPermissionTrouble.permissionDenied;
    } else {
      // 未知のエラーはバナー化せず、次の正常な更新を待つ
      return;
    }
    _recomputeBanner();

    if (isRecording) {
      _forceStopForPermissionTrouble();
    }
  }

  void _recomputeBanner() {
    _locationBannerController.add(_computeBannerState());
  }

  LocationBannerState _computeBannerState() {
    if (_permissionTrouble == _LocationPermissionTrouble.serviceDisabled) {
      return const LocationBannerState(kind: LocationBannerKind.serviceDisabled);
    }
    if (_permissionTrouble == _LocationPermissionTrouble.permissionDenied) {
      return const LocationBannerState(kind: LocationBannerKind.permissionDenied);
    }

    if (_lastGoodPositionAt == null) {
      return const LocationBannerState(kind: LocationBannerKind.neverAcquired);
    }

    final elapsed = DateTime.now().difference(_lastGoodPositionAt!);
    if (elapsed >= _staleThreshold) {
      return LocationBannerState(kind: LocationBannerKind.stalled, elapsedSinceLastGood: elapsed);
    }

    if (_accuracyTroubleCount > 0) {
      return const LocationBannerState(kind: LocationBannerKind.accuracyLow);
    }

    return LocationBannerState.none;
  }

  // 収録中に位置情報の権限/サービスが失われた場合、収録を強制的に終了し保存/破棄を確認する
  Future<void> _forceStopForPermissionTrouble() async {
    if (!isRecording) return;

    final session = _session;
    if (session == null) return;

    // 位置情報が失われている最中なので、最終ポイント取得は試みずそのまま終了する
    await stopRecording(skipFinalPositionFetch: true);

    await showSaveOrDiscardDialog(
      sessionStartedAt: session.startedAt,
      infoMessage: '位置情報の利用が失われたため、収録を停止しました。',
      onDiscard: () => completeSession(doSave: false),
      onSave: (sessionName, moveMethod) => completeSession(
        doSave: true,
        sessionName: sessionName,
        moveMethod: moveMethod
      )
    );
  }

  // start recording
  Future<void> startRecording() async {
    if (isRecording) return;

    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw Exception('位置情報の利用権限が許可されていません。');
    }

    // reflesh _last/current position as initial position
    final currentPosition = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
    );
    _currentPositionController.add(currentPosition);
    _lastPosition = currentPosition;

    final now = DateTime.now();

    // create session
    _session = RecordingSession(
      sessionId: _uuid.v4(),
      startedAt: now,
      endedAt: null,
      totalDistance: 0.0,
      elapsedSeconds: 0,
      elevationGain: 0.0,
      maxAltitude: currentPosition.altitude,
      minAltitude: currentPosition.altitude
    );

    // writing into DB
    await _repo.initSession(
      session: _session!,
    );
    // save current position as initial point of session
    await _repo.addTrackPoint(
      sessionId: _session!.sessionId,
      latitude: currentPosition.latitude,
      longitude: currentPosition.longitude,
      altitude: currentPosition.altitude,
      recordedAt: now
    );

    // initialize tracking-state for UI
    _isRecordingController.add(isRecording);
    _recordingSessionController.add(recordingSession!);

    // start the timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _session = _session!.copyWith(elapsedSeconds: _session!.elapsedSeconds + 1);
      _recordingSessionController.add(recordingSession!);

      if (_session!.elapsedSeconds % 5 == 0) {
        _repo.addTrackPoint(
          sessionId: _session!.sessionId,
          latitude: _lastPosition!.latitude,
          longitude: _lastPosition!.longitude,
          altitude: _lastPosition!.altitude,
          recordedAt: DateTime.now()
        );
      }
    });
  }

  // update position
  Future<void> _onRecordingPositionUpdated(Position currentPosition) async {
    if (!isRecording) return;

    // total distance
    if (_lastPosition != null) {
      final horizontalDistance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        currentPosition.latitude,
        currentPosition.longitude
      );
      
      // check if the currentPosition altitude is valid
      // if not, replace it with _lastPosition's
      final altitudeDiff = (currentPosition.altitude - _lastPosition!.altitude).abs();
      if (altitudeDiff < 0.5 || altitudeDiff > 75.0) {
        currentPosition = Position(
          timestamp: currentPosition.timestamp,
          latitude: currentPosition.latitude,
          longitude: currentPosition.longitude,
          accuracy: currentPosition.accuracy,
          altitude: _lastPosition!.altitude,
          altitudeAccuracy: _lastPosition!.accuracy,
          heading: currentPosition.heading,
          headingAccuracy: currentPosition.headingAccuracy,
          speed: currentPosition.speed,
          speedAccuracy: currentPosition.speedAccuracy
        );
      }

      // calculate distance and add to _totalDistance
      late double distanceMeter;
      if (currentPosition.altitude == _lastPosition!.altitude) {
        distanceMeter = horizontalDistance;
      } else {
        distanceMeter = sqrt(
          pow(horizontalDistance,2) + pow(currentPosition.altitude - _lastPosition!.altitude, 2)
        );
      }

      // update session and screen
      _session = _session!.copyWith(
        totalDistance: _session!.totalDistance + (distanceMeter / 1000.0),
        elevationGain: _session!.elevationGain + max(0.0, currentPosition.altitude - _lastPosition!.altitude),
        maxAltitude: max(_session!.maxAltitude, currentPosition.altitude),
        minAltitude: min(_session!.minAltitude, currentPosition.altitude)
      );
      _recordingSessionController.add(recordingSession!);
    }

    // update _lastPosition
    _lastPosition = currentPosition;
  }

  // stop recording
  Future<void> stopRecording({bool skipFinalPositionFetch = false}) async {
    if (!isRecording) return;

    // end session
    final now = DateTime.now();
    _session = _session!.copyWith(endedAt: now);

    // record final point (位置情報が失われた状態からの強制停止時は取得を試みない)
    if (!skipFinalPositionFetch && _session!.elapsedSeconds % 5 != 0) {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
      );
      _currentPositionController.add(currentPosition);
      _lastPosition = currentPosition;

      await _repo.addTrackPoint(
        sessionId: _session!.sessionId,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
        altitude: currentPosition.altitude,
        recordedAt: now
      );
    }

    // stop the timer
    _timer?.cancel();
    _timer = null;

    // stop recording
  }

  // complete session by save/discard
  Future<void> completeSession({
    required bool doSave,
    String? sessionName,
    MoveMethod? moveMethod
  }) async {
    if (!isRecording) return;

    if (doSave) {
      // save
      await _repo.saveCompletedSession(
        session: _session!,
        name: sessionName!,
        moveMethod: moveMethod!,
        savedAt: DateTime.now(),
      );
    } else {
      await _repo.deleteRecordingSession(session: _session!);
    }

    // reset recording states
    _session = null;
    _isRecordingController.add(isRecording);
    _recordingSessionController.add(recordingSession);
  }

  // for later update of session info
  Future<void> toggleFavorite(Session session) async {
    await _repo.toggleFavorite(session);
  }

  // 保存済みセッション一覧からの削除
  Future<void> deleteSession(Session session) async {
    await _repo.deleteSession(session);
  }

  // 保存済みセッション一覧からの名前・移動手段の編集
  Future<void> updateSessionInfo({
    required Session session,
    required String sessionName,
    required MoveMethod moveMethod,
  }) async {
    await _repo.updateSessionInfo(
      session: session,
      sessionName: sessionName,
      moveMethod: moveMethod,
    );
  }

  void dispose() {
    _positionStreamSubscription?.cancel();
    _timer?.cancel();
    _bannerWatchdogTimer?.cancel();
    _isRecordingController.close();
    _currentPositionController.close();
    _recordingSessionController.close();
    _locationBannerController.close();
  }
}
