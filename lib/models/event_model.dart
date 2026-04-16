class EventModel {
  final int? eventId;
  final String eventName;
  final String? eventDate;
  final String? eventTime;
  final String? host;
  final String? speaker;
  final bool isNew;

  EventModel({
    this.eventId,
    required this.eventName,
    this.eventDate,
    this.eventTime,
    this.host,
    this.speaker,
    this.isNew = false,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) => EventModel(
        eventId: json['event_id'] as int?,
        eventName: json['event_name'] as String? ?? '',
        eventDate: json['event_date'] as String?,
        eventTime: json['event_time'] as String?,
        host: json['host'] as String?,
        speaker: json['speaker'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'event_name': eventName,
        'event_date': eventDate,
        'event_time': eventTime,
        'host': host ?? 'none',
        'speaker': speaker ?? 'none',
      };

  String get displayLabel =>
      '$eventName${eventDate != null ? ' ($eventDate)' : ''}';
}
