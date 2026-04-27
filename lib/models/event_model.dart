/// Model representing an event in the attendance management system.
/// 
/// This model encapsulates event information including basic details,
/// timing, and participant information. It provides JSON serialization
/// and useful utility methods for event display and comparison.
class EventModel {
  final int? eventId;
  final String eventName;
  final String? eventDate;
  final String? eventTime;
  final String? host;
  final String? speaker;
  final String? eventLocation;
  final int? attendeeCount;
  final String? status; // upcoming | ongoing | completed | cancelled
  final bool isNew;

  EventModel({
    this.eventId,
    required this.eventName,
    this.eventDate,
    this.eventTime,
    this.host,
    this.speaker,
    this.eventLocation,
    this.attendeeCount,
    this.status,
    this.isNew = false,
  });

  /// Creates an [EventModel] from a JSON map.
  /// 
  /// Handles null values gracefully and provides defaults where appropriate.
  factory EventModel.fromJson(Map<String, dynamic> json) => EventModel(
        eventId: json['event_id'] as int?,
        eventName: json['event_name'] as String? ?? '',
        eventDate: json['event_date'] as String?,
        eventTime: json['event_time'] as String?,
        host: json['host'] as String?,
        speaker: json['speaker'] as String?,
        eventLocation: json['event_location'] as String?,
        attendeeCount: json['attendee_count'] as int?,
        status: json['status'] as String?,
      );

  /// Converts this [EventModel] to a JSON map.
  /// 
  /// Null values are handled by providing default strings for host and speaker.
  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'event_name': eventName,
        'event_date': eventDate,
        'event_time': eventTime,
        'host': host ?? 'none',
        'speaker': speaker ?? 'none',
        'event_location': eventLocation,
        'attendee_count': attendeeCount,
        'status': status ?? 'upcoming',
      };

  /// Returns a formatted display label combining event name and date.
  /// 
  /// Example: "Team Meeting (2026-04-27)" or "Team Meeting" if no date.
  String get displayLabel =>
      '$eventName${eventDate != null ? ' ($eventDate)' : ''}';

  /// Returns true if this event has all required information filled.
  bool get isComplete =>
      eventId != null &&
      eventName.isNotEmpty &&
      eventDate != null &&
      eventTime != null &&
      eventLocation != null;

  /// Creates a copy of this [EventModel] with the specified fields replaced.
  /// 
  /// Useful for creating modified versions of this model without manual
  /// reassignment of all fields.
  EventModel copyWith({
    int? eventId,
    String? eventName,
    String? eventDate,
    String? eventTime,
    String? host,
    String? speaker,
    String? eventLocation,
    int? attendeeCount,
    String? status,
    bool? isNew,
  }) =>
      EventModel(
        eventId: eventId ?? this.eventId,
        eventName: eventName ?? this.eventName,
        eventDate: eventDate ?? this.eventDate,
        eventTime: eventTime ?? this.eventTime,
        host: host ?? this.host,
        speaker: speaker ?? this.speaker,
        eventLocation: eventLocation ?? this.eventLocation,
        attendeeCount: attendeeCount ?? this.attendeeCount,
        status: status ?? this.status,
        isNew: isNew ?? this.isNew,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventModel &&
          runtimeType == other.runtimeType &&
          eventId == other.eventId &&
          eventName == other.eventName &&
          eventDate == other.eventDate &&
          eventTime == other.eventTime &&
          host == other.host &&
          speaker == other.speaker &&
          eventLocation == other.eventLocation &&
          attendeeCount == other.attendeeCount &&
          status == other.status &&
          isNew == other.isNew;

  @override
  int get hashCode =>
      eventId.hashCode ^
      eventName.hashCode ^
      eventDate.hashCode ^
      eventTime.hashCode ^
      host.hashCode ^
      speaker.hashCode ^
      eventLocation.hashCode ^
      attendeeCount.hashCode ^
      status.hashCode ^
      isNew.hashCode;

  @override
  String toString() =>
      'EventModel(eventId: $eventId, eventName: $eventName, '
      'eventDate: $eventDate, eventTime: $eventTime, '
      'host: $host, speaker: $speaker, '
      'eventLocation: $eventLocation, attendeeCount: $attendeeCount, '
      'status: $status, isNew: $isNew)';
}
