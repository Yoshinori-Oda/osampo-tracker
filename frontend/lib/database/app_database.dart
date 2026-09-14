import 'dart:io';
import 'dart:async';
//import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
//import 'package:uuid/uuid.dart';
import '../models/recording_session.dart';
import '../models/status.dart';
import '../models/move_method.dart';

part 'app_database.g.dart';

class Sessions extends Table {
  // basic info
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text().withLength(min:1, max: 100).nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get status => intEnum<Status>().withDefault(Constant(Status.ended.index))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  // detailed info
  TextColumn get moveMethod => textEnum<MoveMethod>().withDefault(Constant(MoveMethod.walk.name))();
  RealColumn get totalDistance => real().withDefault(const Constant(0.0))();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  RealColumn get elevationGain => real().withDefault(const Constant(0.0))();
  RealColumn get maxAltitude => real().nullable()();
  RealColumn get minAltitude => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TrackPoints extends Table {
  // basic info
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get recordedAt => dateTime()();

  // position info
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
}

@DriftDatabase(tables: [Sessions, TrackPoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Stream<List<Session>> watchAllSessions() {
    return (select(sessions)
        ..where((tbl) => tbl.endedAt.isNotNull())
        ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)]))
      .watch();
  }

  Future<int> initSession({
    required RecordingSession session,
    required String userId,
    }) {
    return into(sessions).insert(
      SessionsCompanion.insert(
        id: session.sessionId,
        userId: userId,
        startedAt: session.startedAt,
        status: Value(Status.inProgress),
      )
    );
  }

  Future<int> addTrackPoint({
    required String sessionId,
    required double latitude,
    required double longitude,
    double? altitude,
    required DateTime recordedAt
    }) {
    return into(trackPoints).insert(
      TrackPointsCompanion.insert(
        sessionId: sessionId,
        latitude: latitude,
        longitude: longitude,
        altitude: Value(altitude),
        recordedAt: recordedAt
      )
    );
  }

  Future<void> saveCompletedSession({
    required RecordingSession session,
    required String name,
    required MoveMethod moveMethod,
    required DateTime savedAt,
  }) {
    return (update(sessions)..where((tbl) => tbl.id.equals(session.sessionId))).write(
      SessionsCompanion(
        name: Value(name),
        status: Value(Status.ended),
        moveMethod: Value(moveMethod),
        totalDistance: Value(session.totalDistance),
        durationSeconds: Value(session.elapsedSeconds),
        elevationGain: Value(session.elevationGain),
        maxAltitude: Value(session.maxAltitude),
        minAltitude: Value(session.minAltitude),
        endedAt: Value(session.endedAt),
        updatedAt: Value(savedAt)
      )
    );
  }

  Future<void> upsertByFetchedData({
    required Session session,
    required List<TrackPoint> tps
  }) async {
    // skip if the sessionId exists and is waiting to be synced
    final localRecord = await (select(sessions)
      ..where((tbl) => tbl.id.equals(session.id)))
    .getSingleOrNull();
    if (localRecord != null && localRecord.status != Status.synced) return;

    // upsert given session
    await transaction(() async {
      await into(sessions).insertOnConflictUpdate(
        SessionsCompanion.insert(
          id: session.id,
          userId: session.userId,
          name: Value(session.name),
          startedAt: session.startedAt,
          endedAt: Value(session.endedAt),
          status: Value(session.status),
          isFavorite: Value(session.isFavorite),
          moveMethod: Value(session.moveMethod),
          totalDistance: Value(session.totalDistance),
          durationSeconds: Value(session.durationSeconds),
          elevationGain: Value(session.elevationGain),
          maxAltitude: Value(session.maxAltitude),
          minAltitude: Value(session.minAltitude),
        )
      );

      // register tracking points if not exists
      if (localRecord == null) {
        await batch((b) {
          b.insertAll(
            trackPoints,
            tps.map((tp) => TrackPointsCompanion.insert(
              sessionId: tp.sessionId,
              recordedAt: tp.recordedAt,
              latitude: tp.latitude,
              longitude: tp.longitude,
              altitude: Value(tp.altitude),
            )),
          );
        });
      }
    });
  }

  Future<void> deleteRecordingSession({
    required RecordingSession session,
    }) {
    return (delete(sessions)..where((tbl) => tbl.id.equals(session.sessionId))).go();
  }

  Future<void> markAsSynced({required String sessionId, required DateTime syncTime}) {
    return (update(sessions)..where((tbl) => tbl.id.equals(sessionId))).write(
      SessionsCompanion(
        status: const Value(Status.synced),
        updatedAt: Value(DateTime.now())
      )
    );
  }

  Future<void> updateSession({
    required Session session,
    required String sessionName,
    required MoveMethod moveMethod,
    required bool isFavorite
  }) {
    return (update(sessions)..where((tbl) => tbl.id.equals(session.id))).write(
      SessionsCompanion(
        status: session.status != Status.ended ? Value(Status.updated) : Value(Status.ended),
        name: Value(sessionName),
        moveMethod: Value(moveMethod),
        isFavorite: Value(isFavorite)
      )
    );
  }

  Future<void> toggleFavorite(Session session) {
    return (update(sessions)..where((tbl) => tbl.id.equals(session.id))).write(
      SessionsCompanion(
        status: session.status != Status.ended ? Value(Status.updated) : Value(Status.ended),
        isFavorite: Value(!session.isFavorite),
        updatedAt: Value(DateTime.now())
      )
    );
  }

  Future<List<TrackPoint>> getTrackPointsForSession(String sessionId) {
    return (select(trackPoints)
        ..where((tbl) => tbl.sessionId.equals(sessionId))
        ..orderBy([(tbl) => OrderingTerm.asc(tbl.recordedAt)]))
      .get();
  }

  Stream<Session> getSessionById(String sessionId) {
    return (select(sessions)
        ..where((tbl) => tbl.id.equals(sessionId)))
      .watchSingle();
  }

  Future<List<Session>> getUnsyncedSessions() {
    return (select(sessions)
      ..where((tbl) => tbl.status.equals(Status.synced.index).not())
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)])
    ).get();
  }
}

// dummy data
// extension AppDatabaseSeedExtension on AppDatabase {
//  Future<void> seedDummyData() async {
//    await delete(trackPoints).go();
//    await delete(sessions).go();
//
//    final uuid = const Uuid();
//    final now = DateTime.now();
//    final random = Random();
//
//    final dummiesSession = [
//      {'name': '夜ラーメン', 'method': 'walk', 'dist': 0.0, 'duration': 3, 'elev': 0.0, 'maxAlt': null, 'minAlt': null, 'daysAgo': 0},
//      {'name': '朝の散歩', 'method': 'walk', 'dist': 3.5, 'duration': 2400, 'elev': 25.0, 'maxAlt': 30.0, 'minAlt': 15.0, 'daysAgo': 2},
//      {'name': '夕方ランニング', 'method': 'run', 'dist': 8.2, 'duration': 3000, 'elev': 60.0, 'maxAlt': 70.0, 'minAlt': 35.0, 'daysAgo': 3},
//      {'name': '休日サイクリング', 'method': 'bicycle', 'dist': 18.0, 'duration': 4500, 'elev': 120.0, 'maxAlt': 65.0, 'minAlt': 20.0, 'daysAgo': 35},
//      {'name': '家族旅行', 'method': 'train', 'dist': 1000.0, 'duration': 8100, 'elev': 800.0, 'maxAlt': 150.0, 'minAlt': 15.0, 'daysAgo': 380}
//    ];
//
//    final userId = '11111111-1111-1111-1111-111111111111';
//
//    await batch((batch) {
//      for (final d in dummiesSession) {
//        final sessionId = uuid.v4();
//        final daysAgo = d['daysAgo'] as int;
//        final startedAt = now.subtract(Duration(days: daysAgo, hours: random.nextInt(3), minutes: random.nextInt(60)));
//        final duration = d['duration'] as int;
//        final endedAt = startedAt.add(Duration(seconds: duration));
//
//        batch.insert(
//          sessions,
//          SessionsCompanion.insert(
//            id: sessionId,
//            userId: userId,
//            name: Value(d['name'] as String),
//            startedAt: startedAt,
//            endedAt: Value(endedAt),
//            isFavorite: Value(false),
//            status: Value(Status.ended),
//            moveMethod: Value(MoveMethod.values.byName(d['method'] as String)),
//            totalDistance: Value(d['dist'] as double),
//            durationSeconds: Value(d['duration'] as int),
//            elevationGain: Value(d['elev'] as double),
//            maxAltitude: Value(d['maxAlt'] as double?),
//            minAltitude: Value(d['minAlt'] as double?)
//          )
//        );
//      }
//    });
//  }
//}


LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));
    print('SQLite DB Path: ${file.path}');
    return NativeDatabase.createInBackground(file);
  });
}