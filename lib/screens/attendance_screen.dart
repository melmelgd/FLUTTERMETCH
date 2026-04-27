// lib/screens/attendance_screen.dart
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/session_model.dart';
import '../models/event_model.dart';
import '../models/attendance_record.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/toast_helper.dart';
import 'qr_scanner_screen.dart';

enum CheckinStep { event, confirm, success }

enum CheckinType { timeIn, timeOut }

enum SubmitMode { online, offline, duplicate, apiError, netError }

class AttendanceScreen extends StatefulWidget {
  final SessionModel session;
  final EventModel? initialEvent;
  const AttendanceScreen({super.key, required this.session, this.initialEvent});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  CheckinStep _step = CheckinStep.event;
  CheckinType _checkinType = CheckinType.timeIn;
  bool _isOnline = true;
  bool _submitting = false;
  SubmitMode? _lastMode;
  String _debugError = '';
  bool _showDebug = false;

  List<EventModel> _events = [];
  EventModel? _selectedEvent;
  bool _isManual = false;
  int _pendingCount = 0;
  List<AttendanceRecord> _history = [];

  final _formKey = GlobalKey<FormState>();
  final _evtNameCtrl = TextEditingController();
  final _evtDateCtrl = TextEditingController();
  final _evtTimeCtrl = TextEditingController();
  final _evtHostCtrl = TextEditingController();
  final _evtSpeakerCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialEvent != null) {
      _selectedEvent = widget.initialEvent;
    }
    _init();
  }

  @override
  void dispose() {
    _evtNameCtrl.dispose();
    _evtDateCtrl.dispose();
    _evtTimeCtrl.dispose();
    _evtHostCtrl.dispose();
    _evtSpeakerCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _isOnline = result != ConnectivityResult.none);
    _setDefaultTime();
    await _loadCachedEvents();
    await _loadHistory();
    await _updatePendingCount();
    if (_isOnline) await _syncNow(silent: true);

    Connectivity().onConnectivityChanged.listen((r) async {
      if (!mounted) return;
      final online = r != ConnectivityResult.none;
      setState(() => _isOnline = online);
      _showNetworkBanner(online);
      if (online) await _syncNow(silent: false);
    });
  }

  void _setDefaultTime() {
    final now = DateTime.now();
    _timeCtrl.text = _fmt24(now);
    _evtDateCtrl.text = DateFormat('yyyy-MM-dd').format(now);
    _evtTimeCtrl.text = _fmt24(now);
  }

  String _fmt24(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _loadCachedEvents() async {
    final cached = await DatabaseService.getCachedEvents();
    if (mounted) setState(() => _events = cached);
    if (!_isOnline) return;
    final fresh = await ApiService.fetchEvents();
    if (fresh.isNotEmpty) {
      await DatabaseService.cacheEvents(fresh);
      if (mounted) setState(() => _events = fresh);
    }
  }

  Future<void> _loadHistory() async {
    final all = await DatabaseService.getAllRecords();
    if (mounted) setState(() => _history = all.take(15).toList());
  }

  Future<void> _updatePendingCount() async {
    final p = await DatabaseService.getPendingRecords();
    if (mounted) setState(() => _pendingCount = p.length);
  }

  Future<void> _syncNow({bool silent = false}) async {
    if (!_isOnline) {
      if (!silent && mounted) {
        showToast(context, 'You are offline.', type: ToastType.warning);
      }
      return;
    }
    final pending = await DatabaseService.getPendingRecords();
    if (pending.isEmpty) {
      if (!silent && mounted) {
        showToast(context, 'Nothing to sync.', type: ToastType.success);
      }
      return;
    }
    if (!silent && mounted) {
      showToast(context, 'Syncing ${pending.length} record(s)…',
          type: ToastType.warning);
    }

    final bulkResult = await ApiService.bulkSync(pending);
    if (bulkResult == null) {
      if (!silent && mounted) {
        showToast(context, '⚠️ Sync failed — server unreachable.',
            type: ToastType.error);
      }
      return;
    }

    for (final res in bulkResult.results) {
      if (res.localId == null) continue;
      if (res.ok) {
        await DatabaseService.markSynced(res.localId!);
      } else {
        await DatabaseService.updateSyncError(
            res.localId!, res.error ?? 'Unknown error');
      }
    }

    await _updatePendingCount();
    await _loadHistory();
    if (!mounted) return;

    if (bulkResult.success > 0) {
      showToast(context, '✅ Synced ${bulkResult.success} record(s)!',
          type: ToastType.success);
    }
    if (bulkResult.errors > 0) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          showToast(context, '⚠️ ${bulkResult.errors} record(s) failed.',
              type: ToastType.warning);
        }
      });
    }
  }

  void _showNetworkBanner(bool online) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        online
            ? '✅ Back online — syncing records…'
            : '⚠️ Offline — data will be saved locally',
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      backgroundColor: online ? AppColors.success : AppColors.warning,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── REPLACE _submitAttendance() in attendance_screen.dart ────────────────────
// The fix: wrap everything in try/finally so _submitting ALWAYS resets to false

  Future<void> _submitAttendance() async {
    setState(() => _submitting = true);

    try {
      final ev = _getEventData();
      final t = _timeCtrl.text;

      final rec = AttendanceRecord(
        attendeeName: widget.session.firstName,
        attendeeCode: widget.session.userId.toString(),
        department: widget.session.accountType,
        attendanceStatus: 'present',
        timeIn: _checkinType == CheckinType.timeIn ? t : null,
        timeOut: _checkinType == CheckinType.timeOut ? t : null,
        isManualEntry: true,
        eventId: ev.isNew ? null : ev.eventId,
        eventData: ev.isNew ? ev.toJson() : null,
        eventName: ev.eventName,
        eventDate: ev.eventDate,
        checkinType: _checkinType == CheckinType.timeIn ? 'in' : 'out',
        timestamp: DateTime.now().toIso8601String(),
        synced: false,
      );

      SubmitMode mode = SubmitMode.offline;

      if (_isOnline) {
        final result = await ApiService.submitAttendance(rec);
        if (result.ok) {
          rec.synced = true;
          final returnedEventId = result.data?['event_id'] as int?;
          if (returnedEventId != null) rec.eventId = returnedEventId;
          mode = result.statusCode == 409
              ? SubmitMode.duplicate
              : SubmitMode.online;
        } else {
          rec.syncError = result.error ?? 'HTTP ${result.statusCode}';
          mode = result.statusCode == 0
              ? SubmitMode.netError
              : SubmitMode.apiError;
          if (mounted) {
            setState(() {
              _debugError = rec.syncError ?? '';
              _showDebug = true;
            });
          }
        }
      }

      await DatabaseService.addRecord(rec);
      await _loadHistory();
      await _updatePendingCount();

      if (mounted) {
        setState(() {
          _lastMode = mode;
          _step = CheckinStep.success;
        });
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Error: $e', type: ToastType.error);
      }
    } finally {
      // ← This ALWAYS runs — spinner always stops
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _scanEventQr() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result is String && result.isNotEmpty) {
      try {
        final data = jsonDecode(result);
        final ev = EventModel.fromJson(data);
        setState(() {
          _isManual = false;
          _selectedEvent = ev;
        });
        if (mounted) {
          showToast(context, 'Event selected: ${ev.eventName}',
              type: ToastType.success);
        }
      } catch (_) {
        if (mounted) {
          showToast(context, 'QR code does not contain valid event data.',
              type: ToastType.error);
        }
      }
    }
  }

  EventModel _getEventData() {
    if (_isManual) {
      return EventModel(
        eventName: _evtNameCtrl.text.trim(),
        eventDate: _evtDateCtrl.text,
        eventTime: _evtTimeCtrl.text,
        host: _evtHostCtrl.text.trim().isEmpty
            ? 'none'
            : _evtHostCtrl.text.trim(),
        speaker: _evtSpeakerCtrl.text.trim().isEmpty
            ? 'none'
            : _evtSpeakerCtrl.text.trim(),
        isNew: true,
      );
    }
    return _selectedEvent!;
  }

  void _goToConfirm() {
    if (_selectedEvent == null && !_isManual) {
      showToast(context, 'Please choose or enter an event.',
          type: ToastType.error);
      return;
    }
    if (_isManual && !(_formKey.currentState?.validate() ?? false)) {
      showToast(context, 'Please complete all required fields.',
          type: ToastType.error);
      return;
    }
    if (_timeCtrl.text.isEmpty) {
      showToast(context, 'Please set a time.', type: ToastType.error);
      return;
    }
    setState(() => _step = CheckinStep.confirm);
  }

  void _checkInAgain() {
    _evtNameCtrl.clear();
    _evtHostCtrl.clear();
    _evtSpeakerCtrl.clear();
    _setDefaultTime();
    setState(() {
      _step = CheckinStep.event;
      _selectedEvent = null;
      _isManual = false;
      _checkinType = CheckinType.timeIn;
      _showDebug = false;
      _lastMode = null;
    });
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History'),
        content:
            const Text('Clear all local records? Unsynced data will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Clear', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await DatabaseService.clearAllRecords();
      await _loadHistory();
      await _updatePendingCount();
      if (mounted) {
        showToast(context, 'History cleared.', type: ToastType.warning);
      }
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(),
          Expanded(
              child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            child: Column(children: [
              if (_showDebug) _buildDebugPanel(),
              if (_pendingCount > 0) _buildSyncBar(),
              _buildStepIndicator(),
              _buildStepContent(),
              const SizedBox(height: 20),
              _buildHistoryCard(),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration:
          const BoxDecoration(gradient: AppColors.attendanceHeaderGradient),
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 14),
      child: Column(children: [
        Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('📋 Attendance Check-In',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _isOnline
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFFBBF24),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(_isOnline ? 'Online' : 'Offline',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Checking in as',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
              Text(widget.session.firstName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('ID',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
              Text('ID: ${widget.session.userId}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('⚠️ Sync Error',
                  style: TextStyle(
                      color: Color(0xFFF87171),
                      fontWeight: FontWeight.w700,
                      fontSize: 13))),
          GestureDetector(
            onTap: () => setState(() => _showDebug = false),
            child: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6)),
          child: Text(_debugError,
              style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontFamily: 'monospace',
                  fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildSyncBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(
            child: Text('⏳ $_pendingCount record(s) pending sync',
                style:
                    const TextStyle(color: Color(0xFF92400E), fontSize: 13))),
        GestureDetector(
          onTap: () => _syncNow(silent: false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(7)),
            child: const Text('Sync Now',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _buildStepIndicator() {
    if (_step == CheckinStep.success) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _StepCircle(
            number: '1',
            label: 'Event',
            isDone: _step != CheckinStep.event,
            isActive: _step == CheckinStep.event),
        _StepLine(done: _step != CheckinStep.event),
        _StepCircle(
            number: '2',
            label: 'Confirm',
            isDone: false,
            isActive: _step == CheckinStep.confirm),
      ]),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case CheckinStep.event:
        return _buildEventCard();
      case CheckinStep.confirm:
        return _buildConfirmCard();
      case CheckinStep.success:
        return _buildSuccessCard();
    }
  }

  // ── STEP 1 ───────────────────────────────────────────────────────
  Widget _buildEventCard() {
    return _Card(
        child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle(icon: '📅', label: 'Event Details'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _FieldLabel('Select Event *'),
                    GestureDetector(
                      onTap: _scanEventQr,
                      child: const Text('📷 SCAN QR',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _buildEventDropdown(),
                if (_isManual) ...[
                  const SizedBox(height: 14),
                  _buildTextField('Event Name *', _evtNameCtrl,
                      hint: 'e.g. Q3 All-Hands Meeting',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 14),
                  _buildDateField('Event Date *', _evtDateCtrl),
                  const SizedBox(height: 14),
                  _buildTimePickerField('Event Time *', _evtTimeCtrl),
                  const SizedBox(height: 14),
                  _buildTextField('Host (optional)', _evtHostCtrl,
                      hint: 'e.g. John Santos'),
                  const SizedBox(height: 14),
                  _buildTextField('Speaker (optional)', _evtSpeakerCtrl,
                      hint: 'e.g. Maria Cruz'),
                ],
                const SizedBox(height: 14),
                const _FieldLabel('Check-In Type *'),
                const SizedBox(height: 8),
                _buildTimeTabs(),
                const SizedBox(height: 14),
                const _FieldLabel('Time *'),
                const SizedBox(height: 5),
                _buildTimePickerField('', _timeCtrl, showLabel: false),
                const SizedBox(height: 4),
                const Text('Defaults to current time. Adjust if needed.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 14),
                _PrimaryButton(
                    label: 'Review & Confirm →', onPressed: _goToConfirm),
              ],
            )));
  }

  Widget _buildEventDropdown() {
    final currentValue =
        _isManual ? '__new__' : _selectedEvent?.eventId?.toString();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        border: Border.all(color: AppColors.border, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: currentValue,
          hint: const Text('— Choose an event —',
              style: TextStyle(color: AppColors.textMuted)),
          items: [
            const DropdownMenuItem(
                value: null,
                child: Text('— Choose an event —',
                    style: TextStyle(color: AppColors.textMuted))),
            const DropdownMenuItem(
                value: '__new__', child: Text('➕ Enter event manually')),
            ..._events.map((ev) => DropdownMenuItem(
                  value: ev.eventId?.toString() ?? '',
                  child: Text(ev.displayLabel, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (val) {
            if (val == null) {
              setState(() {
                _isManual = false;
                _selectedEvent = null;
              });
            } else if (val == '__new__') {
              setState(() {
                _isManual = true;
                _selectedEvent = null;
              });
            } else {
              final ev = _events.firstWhere(
                (e) => e.eventId?.toString() == val,
                orElse: () => _events.first,
              );
              setState(() {
                _isManual = false;
                _selectedEvent = ev;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildTimeTabs() {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        _TimeTab(
          label: '🟢 Time In',
          active: _checkinType == CheckinType.timeIn,
          onTap: () {
            setState(() => _checkinType = CheckinType.timeIn);
            _timeCtrl.text = _fmt24(DateTime.now());
          },
        ),
        _TimeTab(
          label: '🔴 Time Out',
          active: _checkinType == CheckinType.timeOut,
          onTap: () {
            setState(() => _checkinType = CheckinType.timeOut);
            _timeCtrl.text = _fmt24(DateTime.now());
          },
        ),
      ]),
    );
  }

  // ── STEP 2 ───────────────────────────────────────────────────────
  Widget _buildConfirmCard() {
    final ev = _getEventData();
    final rows = [
      ('Name', widget.session.firstName),
      ('ID', widget.session.userId.toString()),
      ('Department', widget.session.accountType),
      ('Event', ev.eventName),
      ('Date', _fmtDate(ev.eventDate)),
      (
        'Check-In',
        _checkinType == CheckinType.timeIn ? '🟢 Time In' : '🔴 Time Out'
      ),
      ('Time', _fmtTime(_timeCtrl.text)),
    ];
    return _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _CardTitle(icon: '✅', label: 'Confirm Your Attendance'),
      ...rows.map((r) => _reviewRow(r.$1, r.$2)),
      const SizedBox(height: 8),
      _GhostButton(
          label: '← Back',
          onPressed: () => setState(() => _step = CheckinStep.event)),
      const SizedBox(height: 8),
      _SuccessButton(
          label: '✅ Submit Attendance',
          loading: _submitting,
          onPressed: _submitting ? null : _submitAttendance),
    ]));
  }

  Widget _reviewRow(String key, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(key.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
        const SizedBox(width: 10),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain))),
      ]),
    );
  }

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return '—';
    try {
      return DateFormat('MMMM d, y').format(DateTime.parse(d));
    } catch (_) {
      return d;
    }
  }

  String _fmtTime(String t) {
    if (t.isEmpty) return '—';
    try {
      final p = t.split(':');
      final h = int.parse(p[0]);
      final m = p[1];
      return '${h % 12 == 0 ? 12 : h % 12}:$m ${h >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return t;
    }
  }

  // ── STEP 3 ───────────────────────────────────────────────────────
  Widget _buildSuccessCard() {
    final msgs = <SubmitMode, ({String icon, String title, String sub})>{
      SubmitMode.online: (
        icon: '🎉',
        title: 'Checked In!',
        sub: 'Saved and synced to server successfully.'
      ),
      SubmitMode.duplicate: (
        icon: '✅',
        title: 'Already Recorded!',
        sub: 'Your attendance was already recorded.'
      ),
      SubmitMode.offline: (
        icon: '💾',
        title: 'Saved Locally!',
        sub: '⚠️ No internet. Will sync when online.'
      ),
      SubmitMode.apiError: (
        icon: '⚠️',
        title: 'Saved Locally',
        sub: 'Server error. Check the debug panel above.'
      ),
      SubmitMode.netError: (
        icon: '📡',
        title: 'Saved Locally',
        sub: 'Could not reach server. Will retry when online.'
      ),
    };
    final m = msgs[_lastMode ?? SubmitMode.offline]!;
    return _Card(
        child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (_, val, child) => Transform.scale(scale: val, child: child),
          child: Text(m.icon, style: const TextStyle(fontSize: 64)),
        ),
        const SizedBox(height: 14),
        Text(m.title,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain)),
        const SizedBox(height: 8),
        Text(m.sub,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textMuted, height: 1.6)),
        const SizedBox(height: 22),
        _PrimaryButton(label: 'Check In Again', onPressed: _checkInAgain),
        const SizedBox(height: 8),
        _GhostButton(
            label: '← Back to Home',
            onPressed: () => Navigator.of(context).pop()),
      ]),
    ));
  }

  // ── History ──────────────────────────────────────────────────────
  Widget _buildHistoryCard() {
    return _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const _CardTitle(icon: '📜', label: 'My Records'),
        TextButton(
          onPressed: _clearHistory,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.bg,
            side: const BorderSide(color: AppColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          child: const Text('Clear',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted)),
        ),
      ]),
      if (_history.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
              child: Column(children: [
            Text('📭', style: TextStyle(fontSize: 40)),
            SizedBox(height: 8),
            Text('No records yet.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ])),
        )
      else
        ..._history.map(_buildHistoryItem),
    ]));
  }

  Widget _buildHistoryItem(AttendanceRecord r) {
    final ts = r.timestamp.isNotEmpty
        ? DateFormat('MMM d, h:mm a').format(DateTime.parse(r.timestamp))
        : '—';
    final isIn = r.checkinType == 'in';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: r.synced ? AppColors.bg : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(
                color: r.synced ? AppColors.success : AppColors.warning,
                width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.attendeeName,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textMain)),
          const SizedBox(height: 2),
          Text('${r.eventName ?? 'Unknown event'} • $ts',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          if (!r.synced && r.syncError != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(5)),
              child: Text('⚠️ ${r.syncError}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.danger)),
            ),
          ],
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _Badge(
            label: isIn ? 'Time In' : 'Time Out',
            bg: isIn ? const Color(0xFFDBEAFE) : const Color(0xFFEDE9FE),
            fg: isIn ? const Color(0xFF1E40AF) : const Color(0xFF5B21B6),
          ),
          const SizedBox(height: 4),
          _Badge(
            label: r.synced ? '✔ Synced' : '⏳ Pending',
            bg: r.synced ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
            fg: r.synced ? const Color(0xFF166534) : const Color(0xFF92400E),
          ),
        ]),
      ]),
    );
  }

  // ── Form field helpers ────────────────────────────────────────────
  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFFAFBFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border, width: 2)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border, width: 2)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.danger, width: 2)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.danger, width: 2)),
      );

  Widget _buildTextField(String label, TextEditingController ctrl,
      {String? hint, String? Function(String?)? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(label),
      const SizedBox(height: 5),
      TextFormField(
          controller: ctrl,
          validator: validator,
          decoration: _inputDec(hint ?? ''),
          style: const TextStyle(fontSize: 16, color: AppColors.textMain)),
    ]);
  }

  Widget _buildDateField(String label, TextEditingController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(label),
      const SizedBox(height: 5),
      GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030));
          if (picked != null) {
            ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
          }
        },
        child: AbsorbPointer(
            child: TextFormField(
                controller: ctrl,
                decoration: _inputDec('YYYY-MM-DD'),
                style:
                    const TextStyle(fontSize: 16, color: AppColors.textMain))),
      ),
    ]);
  }

  Widget _buildTimePickerField(String label, TextEditingController ctrl,
      {bool showLabel = true}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showLabel && label.isNotEmpty) ...[
        _FieldLabel(label),
        const SizedBox(height: 5)
      ],
      GestureDetector(
        onTap: () async {
          final parts = ctrl.text.split(':');
          final init = TimeOfDay(
            hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0,
            minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
          );
          final picked =
              await showTimePicker(context: context, initialTime: init);
          if (picked != null) {
            ctrl.text =
                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          }
        },
        child: AbsorbPointer(
            child: TextFormField(
                controller: ctrl,
                decoration: _inputDec('HH:MM'),
                style:
                    const TextStyle(fontSize: 16, color: AppColors.textMain))),
      ),
    ]);
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2))
          ],
        ),
        child: child,
      );
}

class _CardTitle extends StatelessWidget {
  final String icon, label;
  const _CardTitle({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain)),
        ]),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.4));
}

class _TimeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TimeTab(
      {required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
          child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4)
                  ]
                : null,
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.accent : AppColors.textMuted)),
        ),
      ));
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _PrimaryButton({required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)]),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11))),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ),
      ));
}

class _SuccessButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const _SuccessButton(
      {required this.label, this.loading = false, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF15803D), Color(0xFF16A34A)]),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF15803D).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11))),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
        ),
      ));
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _GhostButton({required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppColors.border, width: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11))),
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w700))));
}

class _StepCircle extends StatelessWidget {
  final String number, label;
  final bool isDone, isActive;
  const _StepCircle(
      {required this.number,
      required this.label,
      this.isDone = false,
      this.isActive = false});
  @override
  Widget build(BuildContext context) {
    final Color bg = isDone
        ? AppColors.success
        : isActive
            ? AppColors.accent
            : AppColors.border;
    final Color fg = (isDone || isActive) ? Colors.white : AppColors.textMuted;
    return Column(children: [
      AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.30),
                          blurRadius: 8,
                          spreadRadius: 2)
                    ]
                  : null),
          child: Center(
              child: Text(isDone ? '✓' : number,
                  style: TextStyle(
                      color: fg, fontSize: 13, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 5),
      Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDone
                  ? AppColors.success
                  : isActive
                      ? AppColors.accent
                      : AppColors.textMuted)),
    ]);
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  const _StepLine({this.done = false});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 50,
          height: 2,
          color: done ? AppColors.success : AppColors.border));
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Badge({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)));
}
