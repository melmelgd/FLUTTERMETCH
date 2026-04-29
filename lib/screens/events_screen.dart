// lib/screens/events_screen.dart
// All Events screen — matches EventFlow UI screenshot

import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/session_model.dart';
import '../utils/app_colors.dart';
import '../utils/toast_helper.dart';
import 'new_event_screen.dart';
import 'event_detail_screen.dart';
import 'upload_screen.dart';
import 'qr_scanner_screen.dart';
import '../services/database_service.dart';
import '../models/attendance_record.dart';
import 'package:intl/intl.dart';

class EventsScreen extends StatefulWidget {
  final SessionModel? session;
  const EventsScreen({super.key, this.session});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<EventModel> _allEvents = [];
  List<EventModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    final events = await DatabaseService.getCachedEvents();
    
    // Update attendee counts from local records for each event
    final updatedEvents = <EventModel>[];
    for (var e in events) {
      final count = await DatabaseService.getEventAttendeeCount(e.eventId, e.eventName);
      updatedEvents.add(e.copyWith(attendeeCount: count > 0 ? count : e.attendeeCount));
    }

    if (mounted) {
      setState(() {
        _allEvents = updatedEvents;
        _filtered = updatedEvents;
      });
    }
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _allEvents
          .where((e) => e.eventName.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _goToAttend(EventModel event) async {
    _showAttendOptions(event);
  }

  void _showAttendOptions(EventModel event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Attendance: ${event.eventName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'How would you like to record attendance?',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Manual Input',
                    color: const Color(0xFF1B2D5B),
                    onTap: () {
                      Navigator.pop(context);
                      _showManualAttendanceDialog(event);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan QR',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrScannerScreen(
                            onScanned: (code) async {
                              String name = 'QR Scanned';
                              String dept = 'N/A';
                              String attendeeCode = code;

                              try {
                                final data = jsonDecode(code);
                                if (data is Map) {
                                  name = data['name'] ?? data['attendee_name'] ?? 'QR Scanned';
                                  dept = data['department'] ?? data['dept'] ?? 'N/A';
                                  attendeeCode = data['id']?.toString() ?? data['code']?.toString() ?? code;
                                }
                              } catch (_) {
                                if (code.contains(',')) {
                                  final parts = code.split(',');
                                  if (parts.length >= 2) {
                                    attendeeCode = parts[0].trim();
                                    name = parts[1].trim();
                                    if (parts.length >= 3) dept = parts[2].trim();
                                  }
                                } else {
                                  final existingName = await DatabaseService.findNameByCode(code);
                                  if (existingName != null) {
                                    name = existingName;
                                  } else if (!RegExp(r'^[0-9]+$').hasMatch(code)) {
                                    name = code;
                                  } else {
                                    name = 'ID: $code';
                                  }
                                }
                              }

                              _recordAttendance(event, attendeeCode, name, department: dept);
                              return false; // Keep scanning continuous
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualAttendanceDialog(EventModel event) {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Attendance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Attendee Name'),
            ),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(labelText: 'Attendee ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && idCtrl.text.isNotEmpty) {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
                _recordAttendance(event, idCtrl.text, nameCtrl.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordAttendance(EventModel event, String code, String name, {String department = 'N/A'}) async {
    final now = DateTime.now();
    final record = AttendanceRecord(
      attendeeName: name,
      attendeeCode: code,
      department: department,
      attendanceStatus: 'present',
      timeIn: DateFormat('HH:mm').format(now),
      eventId: event.eventId,
      eventData: event.toJson(),
      eventName: event.eventName,
      eventDate: event.eventDate,
      checkinType: 'in',
      timestamp: now.toIso8601String(),
      synced: false,
    );

    await DatabaseService.addRecord(record);
    if (mounted) {
      showToast(context, 'Attendance recorded for $name', type: ToastType.success);
    }
  }

  Future<void> _confirmDelete(EventModel event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "${event.eventName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        if (event.eventId != null) {
          // 1. Delete from the actual database
          await DatabaseService.deleteEvent(event.eventId!);
          
          // 2. Update the UI state
          setState(() {
            _allEvents.removeWhere((e) => e.eventId == event.eventId);
            _filtered.removeWhere((e) => e.eventId == event.eventId);
          });
          
          showToast(context, 'Event deleted permanently', type: ToastType.success);
        }
      } catch (e) {
        showToast(context, 'Failed to delete: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          Row(
            children: [
              _buildSeal(),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('City of Ormoc',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text('EVENT MANAGEMENT',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4)),
                  ],
                ),
              ),
              // User initial avatar
              _buildUserAvatar(),
            ],
          ),
          const SizedBox(height: 20),
          // Title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('All Events',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.1)),
                    const SizedBox(height: 4),
                    Text(
                      '${_allEvents.length} event${_allEvents.length != 1 ? 's' : ''}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Gold "+" button
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewEventScreen(session: widget.session),
                    ),
                  );
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5A623),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFF5A623)
                              .withOpacity(0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search events...',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.60), size: 20),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeal() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2), blurRadius: 8)
        ],
      ),
      child: const ClipOval(
        child:
            Icon(Icons.location_city, color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildUserAvatar() {
    final initial =
        (widget.session?.firstName ?? '').isNotEmpty
            ? widget.session!.firstName[0].toUpperCase()
            : 'D';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF4B6CB7),
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white.withOpacity(0.40), width: 1.5),
      ),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded,
                size: 48,
                color: AppColors.textMuted.withOpacity(0.4)),
            const SizedBox(height: 12),
            const Text('No events found',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _buildEventCard(_filtered[i]),
    );
  }

  // ── Event card ────────────────────────────────────────────────────
  Widget _buildEventCard(EventModel event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card top: icon + name + badge ──────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Building icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_outlined,
                      color: Color(0xFF1B2D5B), size: 20),
                ),
                const SizedBox(width: 12),
                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.eventName,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMain),
                            ),
                          ),
                          // Status badge
                          _buildStatusBadge(event.status ?? 'upcoming'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Date + location row
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (event.eventDate != null)
                            _buildMeta(
                                Icons.calendar_today_outlined,
                                event.eventDate!),
                          if (event.eventLocation != null)
                            _buildMeta(
                                Icons.location_on_outlined,
                                event.eventLocation!),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Attendees
                      _buildMeta(
                          Icons.people_outline_rounded,
                          '${event.attendeeCount ?? 0} attendees'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider ────────────────────────────────────────────
          const Divider(height: 1, color: Color(0xFFF0F2F5)),

          // ── Action buttons ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _buildAction(
                  icon: Icons.visibility_outlined,
                  label: 'View',
                  color: const Color(0xFF4B6CB7),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EventDetailScreen(event: event),
                      ),
                    );
                  },
                ),
                _buildAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: const Color(0xFF1B2D5B),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NewEventScreen(
                          session: widget.session,
                          existingEvent: event,
                        ),
                      ),
                    );
                    if (result == true) {
                      _loadEvents();
                    }
                  },
                ),
                _buildAction(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Attend',
                  color: const Color(0xFF10B981),
                  onTap: () => _goToAttend(event),
                ),
                _buildAction(
                  icon: Icons.delete_outline_rounded,
                  label: null,
                  color: AppColors.danger,
                  onTap: () => _confirmDelete(event),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'ongoing':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'completed':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF3730A3);
        break;
      case 'cancelled':
        bg = const Color(0xFFFFE4E4);
        fg = AppColors.danger;
        break;
      default: // upcoming
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0369A1);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }

  Widget _buildMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildAction({
    required IconData icon,
    required String? label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
