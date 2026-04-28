// lib/services/database_service.dart
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import '../models/attendance_record.dart';
import '../models/event_model.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance_user.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
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
            event_id   INTEGER PRIMARY KEY AUTOINCREMENT,
            event_name TEXT,
            event_date TEXT,
            event_time TEXT,
            host       TEXT,
            speaker    TEXT,
            event_location TEXT,
            attendee_count INTEGER DEFAULT 0,
            status         TEXT DEFAULT 'upcoming'
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add missing columns to events_cache one by one to avoid total failure if some exist
          final columns = {
            'event_location': 'TEXT',
            'attendee_count': 'INTEGER DEFAULT 0',
            'status': 'TEXT DEFAULT "upcoming"',
          };

          for (var entry in columns.entries) {
            try {
              await db.execute(
                  'ALTER TABLE events_cache ADD COLUMN ${entry.key} ${entry.value}');
            } catch (e) {
              debugPrint('Column ${entry.key} might already exist: $e');
            }
          }
        }
      },
    );
  }

  static Future<int> saveEvent(EventModel event) async {
    final db = await database;
    final map = {
      'event_name': event.eventName,
      'event_date': event.eventDate,
      'event_time': event.eventTime,
      'host': event.host,
      'speaker': event.speaker,
      'event_location': event.eventLocation,
      'attendee_count': event.attendeeCount ?? 0,
      'status': event.status ?? 'upcoming',
    };

    if (event.eventId != null) {
      map['event_id'] = event.eventId;
      return db.insert('events_cache', map,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      return db.insert('events_cache', map);
    }
  }

  static Future<int> deleteEvent(int eventId) async {
    final db = await database;
    return db.delete('events_cache', where: 'event_id = ?', whereArgs: [eventId]);
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
            'event_location': ev.eventLocation,
            'attendee_count': ev.attendeeCount ?? 0,
            'status': ev.status ?? 'upcoming',
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
              eventLocation: r['event_location'] as String?,
              attendeeCount: r['attendee_count'] as int?,
              status: r['status'] as String?,
            ))
        .toList();
  }
}
