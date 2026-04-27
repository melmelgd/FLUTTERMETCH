// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/event_model.dart';
import '../models/attendance_record.dart';

// ── Base URLs ─────────────────────────────────────────────────────────────────
const String _kBase =
    'https://paleturquoise-cheetah-627304.hostingersite.com/api/gateway/v1';

const String kAttendanceUrl = '$_kBase/attendance/post.php';
const String kLoginUrl = '$_kBase/auth/login.php';

// ─────────────────────────────────────────────────────────────────────────────
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

// ── Login result ──────────────────────────────────────────────────────────────
class LoginResult {
  final bool ok;
  final String? error;
  final int? userId;
  final String? firstName;
  final String? accountType;
  final String? access;
  final String? email;

  const LoginResult({
    required this.ok,
    this.error,
    this.userId,
    this.firstName,
    this.accountType,
    this.access,
    this.email,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
class ApiService {
  // ── Internal POST helper (attendance endpoint) ────────────────────
  static Future<ApiResult> _post(Map<String, dynamic> payload) async {
    try {
      final res = await http
          .post(
            Uri.parse(kAttendanceUrl),
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

  // ── Login with email + password ───────────────────────────────────
  // Calls login.php which does password_verify() server-side.
  static Future<LoginResult> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(kLoginUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return const LoginResult(
            ok: false, error: 'Server returned an invalid response.');
      }

      if (data['status'] == 'success') {
        final user = data['user'] as Map<String, dynamic>? ?? {};
        return LoginResult(
          ok: true,
          userId: user['user_id'] as int?,
          firstName: user['first_name'] as String?,
          accountType: user['account_type'] as String?,
          access: user['access'] as String?,
          email: user['email'] as String?,
        );
      }

      return LoginResult(
        ok: false,
        error: data['message'] as String? ?? 'Login failed.',
      );
    } catch (e) {
      return LoginResult(ok: false, error: e.toString());
    }
  }

  // ── Fetch events list ─────────────────────────────────────────────
  static Future<List<EventModel>> fetchEvents() async {
    try {
      final res = await http
          .get(Uri.parse(kAttendanceUrl.replaceAll('post.php', 'get.php')))
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
  static Future<ApiResult> submitAttendance(AttendanceRecord record) async {
    return _post({
      'action': 'submit_attendance',
      'attendee_name': record.attendeeName,
      'attendee_code': record.attendeeCode,
      'department': record.department,
      'attendance_status': record.attendanceStatus,
      'time_in': record.timeIn,
      'time_out': record.timeOut,
      'is_manual_entry': record.isManualEntry,
      'event_id': record.eventId,
      'event_data': record.eventData,
    });
  }

  // ── POST: bulk_sync ───────────────────────────────────────────────
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
                'is_manual_entry': r.isManualEntry,
                'event_id': r.eventId,
                'event_data': r.eventData,
              })
          .toList(),
    });

    if (result.data == null) return null;

    final summary = result.data!['summary'] as Map<String, dynamic>? ?? {};
    final rawResults = result.data!['results'] as List<dynamic>? ?? [];

    return BulkSyncResult(
      total: summary['total'] as int? ?? 0,
      success: summary['success'] as int? ?? 0,
      errors: summary['errors'] as int? ?? 0,
      results: rawResults.map((r) {
        final m = r as Map<String, dynamic>;
        return BulkRecordResult(
          ok: m['status'] == 'success',
          localId: m['local_id'] as int?,
          attendanceId: m['attendance_id'] as int?,
          error: m['message'] as String?,
        );
      }).toList(),
    );
  }
}
