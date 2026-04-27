import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../utils/app_colors.dart';

class EventDetailScreen extends StatelessWidget {
  final EventModel event;

  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Event Details', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textMain,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.eventName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.calendar_today_outlined, 'Date', event.eventDate ?? 'Not set'),
                  _buildDetailRow(Icons.access_time_outlined, 'Time', event.eventTime ?? 'Not set'),
                  _buildDetailRow(Icons.location_on_outlined, 'Location', event.eventLocation ?? 'Not set'),
                  _buildDetailRow(Icons.person_outline, 'Host', event.host ?? 'Not set'),
                  _buildDetailRow(Icons.mic_none_outlined, 'Speaker', event.speaker ?? 'Not set'),
                  _buildDetailRow(Icons.people_outline, 'Attendees', '${event.attendeeCount ?? 0}'),
                  _buildDetailRow(Icons.info_outline, 'Status', event.status ?? 'upcoming'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textMain)),
            ],
          ),
        ],
      ),
    );
  }
}
