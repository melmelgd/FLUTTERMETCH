// lib/models/attendance_record.dart
import 'dart:convert';

class AttendanceRecord {
  final int? localId;
  final String attendeeName;
  final String attendeeCode;
  final String department;
  final String attendanceStatus;
  final String? timeIn;
  final String? timeOut;
  final bool isManualEntry;
  int? eventId;
  Map<String, dynamic>? eventData;
  final String? eventName;
  final String? eventDate;
  final String checkinType;
  final String timestamp;
  bool synced;
  String? syncError;

  AttendanceRecord({
    this.localId,
    required this.attendeeName,
    required this.attendeeCode,
    required this.department,
    this.attendanceStatus = 'present',
    this.timeIn,
    this.timeOut,
    this.isManualEntry = true,
    this.eventId,
    this.eventData,
    this.eventName,
    this.eventDate,
    this.checkinType = 'in',
    required this.timestamp,
    this.synced = false,
    this.syncError,
  });

  Map<String, dynamic> toDbMap() {
    final map = <String, dynamic>{
      'attendee_name': attendeeName,
      'attendee_code': attendeeCode,
      'department': department,
      'attendance_status': attendanceStatus,
      'time_in': timeIn,
      'time_out': timeOut,
      'is_manual_entry': isManualEntry ? 1 : 0,
      'event_id': eventId,
      'event_data': eventData != null ? jsonEncode(eventData) : null,
      'event_name': eventName,
      'event_date': eventDate,
      'checkin_type': checkinType,
      'timestamp': timestamp,
      'synced': synced ? 1 : 0,
      'sync_error': syncError,
    };
    if (localId != null) map['local_id'] = localId;
    return map;
  }

  factory AttendanceRecord.fromDbMap(Map<String, dynamic> map) {
    Map<String, dynamic>? evtData;
    if (map['event_data'] != null) {
      try {
        evtData =
            jsonDecode(map['event_data'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }
    return AttendanceRecord(
      localId: map['local_id'] as int?,
      attendeeName: map['attendee_name'] as String? ?? '',
      attendeeCode: map['attendee_code'] as String? ?? '',
      department: map['department'] as String? ?? '',
      attendanceStatus: map['attendance_status'] as String? ?? 'present',
      timeIn: map['time_in'] as String?,
      timeOut: map['time_out'] as String?,
      isManualEntry: (map['is_manual_entry'] as int? ?? 0) == 1,
      eventId: map['event_id'] as int?,
      eventData: evtData,
      eventName: map['event_name'] as String?,
      eventDate: map['event_date'] as String?,
      checkinType: map['checkin_type'] as String? ?? 'in',
      timestamp: map['timestamp'] as String? ?? '',
      synced: (map['synced'] as int? ?? 0) == 1,
      syncError: map['sync_error'] as String?,
    );
  }

  Map<String, dynamic> toApiPayload() => {
        'action': 'submit_attendance',
        'attendee_name': attendeeName,
        'attendee_code': attendeeCode,
        'department': department,
        'attendance_status': attendanceStatus,
        'time_in': timeIn,
        'time_out': timeOut,
        'is_manual_entry': isManualEntry,
        'event_id': eventId,
        'event_data': eventData,
      };
}
