// lib/screens/all_events_screen.dart

import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/session_model.dart';
import '../utils/app_colors.dart';
import 'attendance_screen.dart';
import 'new_event_screen.dart';
import '../services/database_service.dart';
import '../utils/toast_helper.dart';
import 'qr_scanner_screen.dart';

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
    if (!mounted) return;
    setState(() {
      _allEvents = events;
      _filteredEvents = events;
      _loaded = true;
    });
  }

  void _onSearch() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEvents = _allEvents.where((e) {
        return e.eventName.toLowerCase().contains(query) ||
            (e.host ?? '').toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onFabPressed() {
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
                      Navigator.pop(context);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              NewEventScreen(session: widget.session),
                        ),
                      );
                      if (result == true) {
                        _loadEvents();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionBtn(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR Scan',
                    color: const Color(0xFFF5A623),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrScannerScreen(
                            onScanned: (code) async {
                              showToast(context, 'Scanned: $code',
                                  type: ToastType.success);
                              return true;
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

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final content = Column(
      children: [
        // ── Header ─────────────────────────────────────────────
        _buildHeader(),
        // ── Search bar ─────────────────────────────────────────
        _buildSearchBar(),
        // ── Event list ─────────────────────────────────────────
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _filteredEvents.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _filteredEvents.length,
                      itemBuilder: (_, i) =>
                          _buildEventCard(_filteredEvents[i]),
                    ),
        ),
      ],
    );

    // If we can't pop, we're likely in the HomeScreen tab view.
    // Use a Material widget instead of a Scaffold to avoid nesting.
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
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        24,
      ),
      child: Row(
        children: [
          // Back button - only show if we can actually go back
          if (canPop) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All Events',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${_allEvents.length} event${_allEvents.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 14, color: AppColors.textMain),
        decoration: const InputDecoration(
          hintText: 'Search events...',
          hintStyle: TextStyle(fontSize: 14, color: AppColors.textMuted),
          prefixIcon: Icon(Icons.search_rounded,
              color: AppColors.textMuted, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    final parts = (event.eventDate ?? '').split(' ');
    final month = parts.isNotEmpty ? parts[0].toUpperCase() : '';
    final day = parts.length > 1 ? parts[1] : '';
    final isUpcoming = (event.status ?? 'upcoming') == 'upcoming';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top row: date badge + name + status badge
          Row(
            children: [
              // Date badge
              Container(
                width: 48,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      month,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Name + host
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.eventName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        event.eventDate ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.person_outline_rounded,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        event.host ?? 'No host',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.people_outline_rounded,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${event.attendeeCount ?? 0} attendees',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ]),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isUpcoming
                      ? const Color(0xFFEEF2FF)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isUpcoming ? 'upcoming' : 'completed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isUpcoming
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 12),

          // Action row: View | Edit | Attend | Delete
          Row(
            children: [
              _buildCardAction(
                icon: Icons.visibility_outlined,
                label: 'View',
                color: AppColors.textMuted,
                onTap: () {
                  // TODO: navigate to event detail
                },
              ),
              _buildActionDivider(),
              _buildCardAction(
                icon: Icons.edit_outlined,
                label: 'Edit',
                color: AppColors.textMuted,
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
              _buildActionDivider(),
              _buildCardAction(
                icon: Icons.how_to_reg_outlined,
                label: 'Attend',
                color: const Color(0xFF059669),
                onTap: () {
                  if (widget.session == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceScreen(
                        session: widget.session!,
                        initialEvent: event,
                      ),
                    ),
                  );
                },
              ),
              _buildActionDivider(),
              _buildCardAction(
                icon: Icons.delete_outline_rounded,
                label: '',
                color: const Color(0xFFEF4444),
                onTap: () => _confirmDelete(event),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionDivider() {
    return Container(width: 1, height: 16, color: const Color(0xFFE5E7EB));
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
