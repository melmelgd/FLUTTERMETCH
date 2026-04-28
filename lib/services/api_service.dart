// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/event_model.dart';
import '../models/attendance_record.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ↓ Replace with your actual Hostinger domain
//  Example: 'https://yourdomain.com/gateway/v1/attendance/post.php'
// ─────────────────────────────────────────────────────────────────────────────
const String kApiBase =
    'https://paleturquoise-cheetah-627304.hostingersite.com/api/gateway/v1/attendance/post.php';

// ─── Response models ──────────────────────────────────────────────────────────

class ApiResult {
  final bool ok;
  final int statusCode;
  final Map<String, dynamic>? data;
  final String? error;

  const ApiResult({
    required this.ok,
    required this.statusCode,
    this.data,
    this.error,
  });
}

class BulkRecordResult {
  final bool ok;
  final int? localId;
  final int? attendanceId;
  final String? error;

  const BulkRecordResult({
    required this.ok,
    this.localId,
    this.attendanceId,
    this.error,
  });
}

class BulkSyncResult {
  final int total;
  final int success;
  final int errors;
  final List<BulkRecordResult> results;

  const BulkSyncResult({
    required this.total,
    required this.success,
    required this.errors,
    required this.results,
  });
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ApiService {
  // ── Internal POST helper ─────────────────────────────────────────
  static Future<ApiResult> _post(Map<String, dynamic> payload) async {
    try {
      final res = await http
          .post(
            Uri.parse(kApiBase),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        final preview =
            res.body.length > 300 ? res.body.substring(0, 300) : res.body;
        return ApiResult(
          ok: false,
          statusCode: res.statusCode,
          error: 'Non-JSON response: $preview',
        );
      }

      // 409 = duplicate attendance — treated as ok
      final ok = data['status'] == 'success' || res.statusCode == 409;
      return ApiResult(
        ok: ok,
        statusCode: res.statusCode,
        data: data,
        error:
            ok ? null : (data['message'] as String? ?? 'Unknown server error'),
      );
    } catch (e) {
      return ApiResult(ok: false, statusCode: 0, error: e.toString());
    }
  }

  // ── GET → fetch events list ───────────────────────────────────────
  // Your post.php only handles POST, so events are fetched
  // via a separate GET endpoint — update the URL below if needed.
  static Future<List<EventModel>> fetchEvents() async {
    try {
      final res = await http
          .get(
            Uri.parse(kApiBase.replaceAll('post.php', 'get.php')),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] == 'success' && body['events'] != null) {
        return (body['events'] as List)
            .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── POST: create_event ────────────────────────────────────────────
  // Required by PHP: event_name, event_date, event_time
  // Optional:        host, speaker
  static Future<ApiResult> createEvent(EventModel event) async {
    return _post({
      'action': 'create_event',
      'event_name': event.eventName,
      'event_date': event.eventDate ?? '',
      'event_time': event.eventTime ?? '',
      'host': event.host ?? 'none',
      'speaker': event.speaker ?? 'none',
    });
  }

  // ── POST: submit_attendance ───────────────────────────────────────
  // Required by PHP: attendee_name, attendance_status
  // Optional:        attendee_code, department, event_id,
  //                  event_data (offline), time_in, time_out,
  //                  is_manual_entry
  static Future<ApiResult> submitAttendance(AttendanceRecord record) async {
    return _post({
      'action': 'submit_attendance',
      'attendee_name': record.attendeeName,
      'attendee_code': record.attendeeCode,
      'department': record.department,
      'attendance_status': record.attendanceStatus,
      'time_in': record.timeIn,
      'time_out': record.timeOut,
      'is_manual_entry': record.isManualEntry ? 1 : 0,
      // event_id  → pass when event already exists in DB
      // event_data → pass when created offline (PHP creates it on-the-fly)
      'event_id': record.eventId,
      'event_data': record.eventData,
    });
  }

  // ── POST: bulk_sync ───────────────────────────────────────────────
  // Sends all pending local records in one request.
  // PHP returns { status, summary: {total,success,errors}, results:[...] }
  static Future<BulkSyncResult?> bulkSync(
      List<AttendanceRecord> pending) async {
    if (pending.isEmpty) return null;

    final result = await _post({
      'action': 'bulk_sync',
      'records': pending
          .map((r) => {
                'local_id': r.localId,
                'attendee_name': r.attendeeName,
                'attendee_code': r.attendeeCode,
                'department': r.department,
                'attendance_status': r.attendanceStatus,
                'time_in': r.timeIn,
                'time_out': r.timeOut,
                'is_manual_entry': r.isManualEntry ? 1 : 0,
                'event_id': r.eventId,
                'event_data': r.eventData,
              })
          .toList(),
    });

    if (result.data == null) return null;

    final summary = result.data!['summary'] as Map<String, dynamic>? ?? {};
    final rawResults = result.data!['results'] as List<dynamic>? ?? [];

    int? parseId(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      return int.tryParse(val.toString());
    }

    return BulkSyncResult(
      total: parseId(summary['total']) ?? 0,
      success: parseId(summary['success']) ?? 0,
      errors: parseId(summary['errors']) ?? 0,
      results: rawResults.map((r) {
        final m = r as Map<String, dynamic>;
        return BulkRecordResult(
          ok: m['status'] == 'success',
          localId: parseId(m['local_id']),
          attendanceId: parseId(m['attendance_id']),
          error: m['message'] as String?,
        );
      }).toList(),
    );
  }
}
