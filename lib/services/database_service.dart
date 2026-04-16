// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attendance_record.dart';
import '../models/event_model.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'attendance_user.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE records (
            local_id          INTEGER PRIMARY KEY AUTOINCREMENT,
            attendee_name     TEXT,
            attendee_code     TEXT,
            department        TEXT,
            attendance_status TEXT DEFAULT 'present',
            time_in           TEXT,
            time_out          TEXT,
            is_manual_entry   INTEGER DEFAULT 1,
            event_id          INTEGER,
            event_data        TEXT,
            event_name        TEXT,
            event_date        TEXT,
            checkin_type      TEXT DEFAULT 'in',
            timestamp         TEXT,
            synced            INTEGER DEFAULT 0,
            sync_error        TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE events_cache (
            event_id   INTEGER PRIMARY KEY,
            event_name TEXT,
            event_date TEXT,
            event_time TEXT,
            host       TEXT,
            speaker    TEXT
          )
        ''');
      },
    );
  }

  static Future<int> addRecord(AttendanceRecord record) async {
    final db = await database;
    final map = record.toDbMap();
    map.remove('local_id');
    return db.insert('records', map);
  }

  static Future<List<AttendanceRecord>> getAllRecords() async {
    final db = await database;
    final rows = await db.query('records', orderBy: 'local_id DESC');
    return rows.map(AttendanceRecord.fromDbMap).toList();
  }

  static Future<List<AttendanceRecord>> getPendingRecords() async {
    final db = await database;
    final rows = await db.query('records', where: 'synced = ?', whereArgs: [0]);
    return rows.map(AttendanceRecord.fromDbMap).toList();
  }

  static Future<void> markSynced(int localId) async {
    final db = await database;
    await db.update('records', {'synced': 1, 'sync_error': null},
        where: 'local_id = ?', whereArgs: [localId]);
  }

  static Future<void> updateSyncError(int localId, String error) async {
    final db = await database;
    await db.update('records', {'sync_error': error},
        where: 'local_id = ?', whereArgs: [localId]);
  }

  static Future<void> clearAllRecords() async {
    final db = await database;
    await db.delete('records');
  }

  static Future<void> cacheEvents(List<EventModel> events) async {
    final db = await database;
    final batch = db.batch();
    for (final ev in events) {
      batch.insert(
          'events_cache',
          {
            'event_id': ev.eventId,
            'event_name': ev.eventName,
            'event_date': ev.eventDate,
            'event_time': ev.eventTime,
            'host': ev.host,
            'speaker': ev.speaker,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<EventModel>> getCachedEvents() async {
    final db = await database;
    final rows = await db.query('events_cache', orderBy: 'event_date DESC');
    return rows
        .map((r) => EventModel(
              eventId: r['event_id'] as int?,
              eventName: r['event_name'] as String? ?? '',
              eventDate: r['event_date'] as String?,
              eventTime: r['event_time'] as String?,
              host: r['host'] as String?,
              speaker: r['speaker'] as String?,
            ))
        .toList();
  }
}
