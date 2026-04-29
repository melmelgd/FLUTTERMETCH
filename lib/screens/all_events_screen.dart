// lib/screens/all_events_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/event_model.dart';
import '../models/session_model.dart';
import '../utils/app_colors.dart';
import '../widgets/app_header.dart';
import 'new_event_screen.dart';
import '../services/database_service.dart';
import '../utils/toast_helper.dart';
import 'qr_scanner_screen.dart';
import 'event_detail_screen.dart';
import 'upload_screen.dart';
import '../models/attendance_record.dart';
import 'package:intl/intl.dart';

class AllEventsScreen extends StatefulWidget {
  final SessionModel? session;

  const AllEventsScreen({super.key, this.session});

  @override
  State<AllEventsScreen> createState() => _AllEventsScreenState();
}

class _AllEventsScreenState extends State<AllEventsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];
  bool _loaded = false;
  String _selectedStatus = 'All';
  int _pendingCount = 0;

  final List<String> _statuses = [
    'All',
    'Upcoming',
    'Ongoing',
    'Completed',
    'Cancelled'
  ];

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _checkPending();
    _searchController.addListener(_onSearch);
  }

  Future<void> _checkPending() async {
    final p = await DatabaseService.getPendingRecords();
    if (mounted) setState(() => _pendingCount = p.length);
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

    if (!mounted) return;
    setState(() {
      _allEvents = updatedEvents;
      _filteredEvents = updatedEvents;
      _loaded = true;
    });
  }

  void _onSearch() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEvents = _allEvents.where((e) {
        final matchesSearch = e.eventName.toLowerCase().contains(query) ||
            (e.host ?? '').toLowerCase().contains(query);
        final matchesStatus = _selectedStatus == 'All' ||
            (e.status?.toLowerCase() == _selectedStatus.toLowerCase());
        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  void _onFabPressed() async {
    final result = await showModalBottomSheet<bool>(
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
            const Text(
              'Create New Event',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select how you want to add the event',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.edit_note_rounded,
                    label: 'Manual Entry',
                    color: const Color(0xFF1B2D5B),
                    onTap: () async {
                      final added = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              NewEventScreen(session: widget.session),
                        ),
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context, added == true);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR Scan',
                    color: const Color(0xFFF5A623),
                    onTap: () async {
                      final added = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrScannerScreen(
                            onScanned: (code) async {
                              // logic for processing QR...
                              return true;
                            },
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context, added == true);
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

    if (result == true) {
      _loadEvents();
    }
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
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
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

  String get _userInitial {
    final name = widget.session?.firstName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : 'D';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final content = Column(
      children: [
        // ── Header ─────────────────────────────────────────────
        _buildHeader(),
        // ── Event list ─────────────────────────────────────────
        Expanded(
          child: Container(
            color: const Color(0xFFF1F5F9), // Light background like image
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _buildStatusFilters(),
                      Expanded(
                        child: _filteredEvents.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                    top: 10, bottom: 100, left: 16, right: 16),
                                itemCount: _filteredEvents.length,
                                itemBuilder: (_, i) =>
                                    _buildEventCard(_filteredEvents[i]),
                              ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );

    // If we can't pop, we're likely in the HomeScreen tab view.
    if (!canPop) {
      return Material(
        color: AppColors.bg,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: content,
    );
  }

  // ── Header ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    final canPop = Navigator.of(context).canPop();
    return AppHeader(
      userInitial: _userInitial,
      pendingCount: _pendingCount,
      showBackButton: canPop,
      onNotificationTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UploadScreen()),
        );
        _checkPending();
      },
      onAvatarTap: () {
        // Handle avatar tap if needed
      },
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Events',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    '${_allEvents.length} events total',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _onFabPressed,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2563EB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 24),
                ),
              )
            ],
          ),
          const SizedBox(height: 18),
          _buildSearchBar(),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _statuses.length,
        itemBuilder: (context, index) {
          final status = _statuses[index];
          final isSelected = _selectedStatus == status;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(status),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedStatus = status;
                  _onSearch();
                });
              },
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF2563EB),
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(
                color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0),
              ),
            ),
          );
        },
      ),
    );
  }



  // ── Search bar ─────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
          )
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
        decoration: InputDecoration(
          hintText: 'Search events...',
          hintStyle: const TextStyle(fontSize: 15, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_rounded,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No events found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different search or create a new event',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Event card ────────────────────────────────────────────────
  Widget _buildEventCard(EventModel event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Building Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.account_balance_rounded,
                      size: 32, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              event.eventName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          _buildStatusBadge(event.status ?? 'upcoming'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildCardMeta(Icons.calendar_today_outlined, event.eventDate ?? ''),
                          const SizedBox(width: 12),
                          _buildCardMeta(Icons.location_on_outlined, event.eventLocation ?? 'Ormoc City'),
                          const SizedBox(width: 12),
                          _buildCardMeta(Icons.people_outline_rounded, '${event.attendeeCount ?? 0} attendees'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          // Actions Row
          IntrinsicHeight(
            child: Row(
              children: [
                _buildCardAction(
                  icon: Icons.visibility_outlined,
                  label: 'View',
                  color: const Color(0xFF64748B),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EventDetailScreen(event: event),
                      ),
                    );
                  },
                ),
                _buildVerticalDivider(),
                _buildCardAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: const Color(0xFF2563EB),
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
                _buildVerticalDivider(),
                _buildCardAction(
                  icon: Icons.group_outlined,
                  label: 'Attend',
                  color: const Color(0xFF059669),
                  onTap: () {
                    if (widget.session == null) return;
                    _showAttendOptions(event);
                  },
                ),
                _buildVerticalDivider(),
                _buildCardAction(
                  icon: Icons.delete_outline_rounded,
                  label: '',
                  color: const Color(0xFFEF4444),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF3B82F6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.toLowerCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3B82F6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMeta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
              fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildCardAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      flex: label.isEmpty ? 0 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return const VerticalDivider(
      width: 1,
      thickness: 1,
      color: Color(0xFFF1F5F9),
      indent: 12,
      endIndent: 12,
    );
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
                              if (mounted) _loadEvents(); // Refresh UI while scanning
                              return false; // Keep scanning
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

  void _showManualAttendanceDialog(EventModel event) {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Manual Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Attendee Name',
                hintText: 'Enter full name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                labelText: 'Attendee ID / Code',
                hintText: 'Enter ID number',
              ),
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
              } else {
                showToast(context, 'Please fill all fields', type: ToastType.warning);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B2D5B),
              foregroundColor: Colors.white,
            ),
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
    
    // Auto-update event status to "Ongoing" if it's currently "Upcoming"
    if (event.status?.toLowerCase() == 'upcoming') {
      final updatedEvent = event.copyWith(status: 'ongoing');
      await DatabaseService.saveEvent(updatedEvent);
    }

    if (mounted) {
      showToast(context, 'Attendance recorded for $name', type: ToastType.success);
    }
  }

  Future<void> _confirmDelete(EventModel event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
            'Are you sure you want to delete "${event.eventName}"?',
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        if (event.eventId != null) {
          await DatabaseService.deleteEvent(event.eventId!);
          setState(() {
            _allEvents.removeWhere((e) => e.eventId == event.eventId);
            _filteredEvents.removeWhere((e) => e.eventId == event.eventId);
          });
          if (mounted) {
            showToast(context, 'Event deleted successfully',
                type: ToastType.success);
          }
        }
      } catch (e) {
        if (mounted) {
          showToast(context, 'Failed to delete event: $e',
              type: ToastType.error);
        }
      }
    }
  }
}
