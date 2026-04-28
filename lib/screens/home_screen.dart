// lib/screens/home_screen.dart — uses AppBottomNavBar

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/session_model.dart';
import '../models/event_model.dart';
import '../services/session_service.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/bottom_nav_bar.dart';
import '../main.dart';
import 'all_events_screen.dart';
import 'new_event_screen.dart';
import 'settings_screen.dart';
import 'upload_screen.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SessionModel? _session;
  bool _isOnline = true;
  int _pendingCount = 0;
  int _selectedTab = 0;
  bool _loaded = false;
  List<EventModel> _upcomingEvents = [];
  int _totalEvents = 0;
  int _completedEvents = 0;
  int _totalAttendees = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = await SessionService.getSession();
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() {
      _session = session;
      _isOnline = result != ConnectivityResult.none;
      _loaded = true;
    });
    await _loadEvents();
    await _checkPending();

    Connectivity().onConnectivityChanged.listen((r) {
      if (!mounted) return;
      setState(() => _isOnline = r != ConnectivityResult.none);
      if (_isOnline) _checkPending();
    });
  }

  Future<void> _loadEvents() async {
    final cached = await DatabaseService.getCachedEvents();
    if (!mounted) return;
    setState(() {
      _totalEvents = cached.length;
      _completedEvents = 0; // Logic for completed could be added later
      _totalAttendees = 0; // Total attendees across events
      _upcomingEvents = cached;
    });
  }

  Future<void> _checkPending() async {
    final p = await DatabaseService.getPendingRecords();
    if (mounted) setState(() => _pendingCount = p.length);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await SessionService.clearSession();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppRouter()),
          (_) => false,
        );
      }
    }
  }

  Future<void> _goToAttendance({EventModel? initialEvent}) async {
    if (_session == null) return;
    // AttendanceScreen removed
    showToast(context, 'Attendance Screen Removed', type: ToastType.warning);
    await _checkPending();
    await _loadEvents();
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
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
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
                          builder: (_) => NewEventScreen(session: _session),
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
                    onTap: () async {
                      Navigator.pop(context);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const QrScannerScreen(),
                        ),
                      );
                      if (!mounted) return;
                      if (result is String && result.isNotEmpty) {
                        try {
                          final data = jsonDecode(result);
                          final ev = EventModel.fromJson(data);
                          _goToAttendance(initialEvent: ev);
                        } catch (_) {
                          if (mounted) {
                            showToast(context, 'Invalid QR data',
                                type: ToastType.error);
                          }
                        }
                      }
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

  String get _userInitial {
    final name = _session?.firstName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_selectedTab == 0) _buildHeader(),
            if (_selectedTab == 0 && _isOnline && _pendingCount > 0)
              _buildSyncNotice(),
            Expanded(child: _buildTabContent()),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        selectedIndex: _selectedTab,
        onTabChanged: (i) => setState(() => _selectedTab = i),
        onFabPressed: _onFabPressed,
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildBody();
      case 1:
        return AllEventsScreen(session: _session);
      case 2:
        return const UploadScreen();
      case 3:
        return SettingsScreen(session: _session);
      default:
        return _buildBody();
    }
  }
  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              GestureDetector(
                onTap: _logout,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B6CB7),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.40),
                        width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      _userInitial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Good day!',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Ormoc City Events',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.1)),
          const SizedBox(height: 4),
          Text('Manage events & attendance',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w400)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _buildDarkStatCard(
                      label: 'Total Events',
                      value: _totalEvents.toString(),
                      icon: Icons.calendar_today_outlined)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildDarkStatCard(
                      label: 'Attendees',
                      value: _totalAttendees.toString(),
                      icon: Icons.people_outline_rounded)),
            ],
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
              color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)
        ],
      ),
      child: const ClipOval(
        child:
            Icon(Icons.location_city, color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildDarkStatCard(
      {required String label,
      required String value,
      required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: Colors.white70, size: 15),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.0)),
        ],
      ),
    );
  }

  // ── Sync notice ───────────────────────────────────────────────────
  Widget _buildSyncNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '⏳ $_pendingCount attendance record(s) pending sync',
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _goToAttendance,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('Sync Now',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: _buildLightStatCard(
                      label: 'Upcoming',
                      value: _upcomingEvents.length.toString(),
                      icon: Icons.access_time_rounded,
                      iconColor: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildLightStatCard(
                      label: 'Completed',
                      value: _completedEvents.toString(),
                      icon: Icons.check_circle_outline_rounded,
                      iconColor: const Color(0xFF10B981))),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Upcoming Events',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AllEventsScreen(session: _session),
                  ),
                ),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('See all',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_upcomingEvents.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14)),
              child: const Center(
                child: Text('No upcoming events',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            )
          else
            Column(
                children: _upcomingEvents
                    .map((e) => _buildEventCard(e))
                    .toList()),
        ],
      ),
    );
  }

  Widget _buildLightStatCard(
      {required String label,
      required String value,
      required IconData icon,
      required Color iconColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: iconColor)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500)),
          ]),
        ],
      ),
    );
  }

  Widget _buildEventCard(EventModel event) {
    String month = '';
    String day = '';

    try {
      if (event.eventDate != null && event.eventDate!.isNotEmpty) {
        final date = DateTime.parse(event.eventDate!);
        month = DateFormat('MMM').format(date).toUpperCase();
        day = date.day.toString();
      }
    } catch (_) {
      // Fallback to old splitting if parsing fails
      final parts = (event.eventDate ?? '').split(' ');
      month = parts.isNotEmpty ? parts[0].toUpperCase() : '';
      day = parts.length > 1 ? parts[1] : '';
    }

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
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 54,
            decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(month,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(day,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.0)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.eventName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain)),
                const SizedBox(height: 5),
                Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: Color(0xFFE05C8A),
                          shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(
                      event.host ??
                          event.eventTime ??
                          'No details',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500)),
                ]),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _goToAttendance(initialEvent: event),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // Removed unused _buildSettingItem
}
