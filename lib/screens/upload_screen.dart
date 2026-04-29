import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../utils/toast_helper.dart';
import '../models/attendance_record.dart';
import '../models/event_model.dart';
import '../models/session_model.dart';
import '../services/session_service.dart';
import 'qr_scanner_screen.dart';

class UploadScreen extends StatefulWidget {
  final String? initialEvent;
  const UploadScreen({super.key, this.initialEvent});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _isSyncing = false;
  List<AttendanceRecord> _records = [];
  bool _isLoading = true;
  String? _selectedEvent;
  List<String> _eventNames = [];
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIds = {};
  SessionModel? _session;

  @override
  void initState() {
    super.initState();
    _selectedEvent = widget.initialEvent;
    _init();
  }

  Future<void> _init() async {
    _session = await SessionService.getSession();
    await _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await DatabaseService.getAllRecords();
    if (mounted) {
      final events = records
          .map((r) => r.eventName)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _records = records;
        _eventNames = events;
        _isLoading = false;
        // Do not auto-select if we already have a selection or if we want to see all by default
      });
    }
  }

  void _showEventPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
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
              const SizedBox(height: 20),
              const Text(
                'Filter by Event',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1B2D5B)),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Icon(Icons.apps_rounded, color: _selectedEvent == null ? const Color(0xFF1B2D5B) : Colors.grey),
                      title: Text(
                        'All Events',
                        style: TextStyle(
                          fontWeight: _selectedEvent == null ? FontWeight.bold : FontWeight.normal,
                          color: _selectedEvent == null ? const Color(0xFF1B2D5B) : Colors.black87,
                        ),
                      ),
                      trailing: _selectedEvent == null ? const Icon(Icons.check_circle, color: Color(0xFF10B981)) : null,
                      onTap: () {
                        setState(() => _selectedEvent = null);
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(height: 1),
                    ..._eventNames.map((e) => ListTile(
                          leading: Icon(Icons.event_available_rounded, 
                              color: _selectedEvent == e ? const Color(0xFF1B2D5B) : Colors.grey),
                          title: Text(
                            e,
                            style: TextStyle(
                              fontWeight: _selectedEvent == e ? FontWeight.bold : FontWeight.normal,
                              color: _selectedEvent == e ? const Color(0xFF1B2D5B) : Colors.black87,
                            ),
                          ),
                          trailing: _selectedEvent == e ? const Icon(Icons.check_circle, color: Color(0xFF10B981)) : null,
                          onTap: () {
                            setState(() => _selectedEvent = e);
                            Navigator.pop(context);
                          },
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  List<AttendanceRecord> get _filteredRecords {
    var filtered = _records;
    if (_selectedEvent != null) {
      filtered = filtered.where((r) => r.eventName == _selectedEvent).toList();
    }
    
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((r) => 
        r.attendeeName.toLowerCase().contains(query)
      ).toList();
    }
    
    return filtered;
  }

  Future<void> _startSync() async {
    final pending = _records.where((r) => r.synced == false).toList();
    if (pending.isEmpty) {
      if (mounted) showToast(context, 'No pending records to sync', type: ToastType.info);
      return;
    }

    setState(() => _isSyncing = true);

    try {
      // 1. First, ensure all events in the pending records exist on the server
      final uniqueEvents = <String, EventModel>{};
      for (var r in pending) {
        if (r.eventName != null && r.eventData != null) {
          uniqueEvents[r.eventName!] = EventModel.fromJson(r.eventData!);
        }
      }

      for (var entry in uniqueEvents.entries) {
        final eventName = entry.key;
        final event = entry.value;

        // Try to create the event on server. 
        // If it already exists, the server should return the existing ID or a 409.
        final res = await ApiService.createEvent(event);
        if (res.ok && res.data != null && res.data!['event_id'] != null) {
          final serverId = int.tryParse(res.data!['event_id'].toString());
          if (serverId != null) {
            await DatabaseService.updateEventIdForRecords(eventName, serverId);
          }
        }
      }

      // 2. Reload records to get the updated event_ids before bulk sync
      final updatedRecords = await DatabaseService.getAllRecords();
      final updatedPending = updatedRecords.where((r) => r.synced == false).toList();

      // 3. Perform bulk sync with verified event_ids
      final result = await ApiService.bulkSync(updatedPending);
      if (result != null) {
        int successCount = 0;
        for (var res in result.results) {
          if (res.ok && res.localId != null) {
            await DatabaseService.markSynced(res.localId!);
            successCount++;
          } else if (res.localId != null && res.error != null) {
            await DatabaseService.updateSyncError(res.localId!, res.error!);
          }
        }

        if (mounted) {
          showToast(
            context,
            'Sync completed: $successCount successful, ${result.errors} errors',
            type: successCount > 0 ? ToastType.success : ToastType.error,
          );
        }
      } else {
        if (mounted) showToast(context, 'Sync failed: No response from server', type: ToastType.error);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Sync error: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _loadRecords();
      }
    }
  }

  void _onScanAttendee() async {
    if (_selectedEvent == null) {
      showToast(context, 'Please select an event first', type: ToastType.warning);
      _showEventPicker();
      return;
    }

    final cachedEvents = await DatabaseService.getCachedEvents();
    final event = cachedEvents.firstWhere(
      (e) => e.eventName == _selectedEvent,
      orElse: () => EventModel(
          eventName: _selectedEvent!,
          eventDate: DateFormat('yyyy-MM-dd').format(DateTime.now())),
    );

    final result = await Navigator.push(
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
                // Not JSON or CSV, try looking up in DB or using code as name
                final existingName = await DatabaseService.findNameByCode(code);
                if (existingName != null) {
                  name = existingName;
                } else if (!RegExp(r'^[0-9]+$').hasMatch(code)) {
                  // If it has letters, it might be the name itself
                  name = code;
                } else {
                  // If it's just numbers, it's an ID
                  name = 'ID: $code';
                }
              }
            }

            await _recordAttendance(event, attendeeCode, name, department: dept);
            return true;
          },
        ),
      ),
    );

    if (result != null) {
      _loadRecords();
    }
  }

  Future<void> _recordAttendance(
      EventModel event, String code, String name, {String department = 'N/A'}) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _records.where((r) => r.synced == false).length;
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(pendingCount),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildStatsBar(filtered),
                  _buildSearchAndActionRow(),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: CircularProgressIndicator(),
                        )
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : _buildAttendanceList(filtered),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int pendingCount) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      color: const Color(0xFFF1F5F9),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 8,
        20,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPop) ...[
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF64748B),
                      size: 16,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('City of Ormoc',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800)),
                    Text('EVENT MANAGEMENT',
                        style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4)),
                  ],
                ),
              ),
              // Notification Bell (Static here since we are already on this screen)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                        )
                      ],
                    ),
                    child: const Icon(Icons.notifications_none_rounded,
                        color: Color(0xFF475569)),
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              _buildAvatar(),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _showEventPicker,
                    child: Row(
                      children: [
                        Text(
                          _selectedEvent ?? 'All Attendance',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                  Text(
                    '${_records.length} records total',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (pendingCount > 0)
                GestureDetector(
                  onTap: _isSyncing ? null : _startSync,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        if (_isSyncing)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        else
                          const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _isSyncing ? 'Syncing...' : 'Sync Now',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSearchBar(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final name = _session?.firstName ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

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
        onChanged: (v) => setState(() {}),
        style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
        decoration: const InputDecoration(
          hintText: 'Search attendees...',
          hintStyle: TextStyle(fontSize: 15, color: Color(0xFF94A3B8)),
          prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 22),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildStatsBar(List<AttendanceRecord> filtered) {
    final synced = filtered.where((r) => r.synced == true).length;
    final pending = filtered.where((r) => r.synced == false).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _buildStatCard('Total', filtered.length.toString(), const Color(0xFF0F172A), const Color(0xFFF1F5F9)),
          const SizedBox(width: 10),
          _buildStatCard('Synced', synced.toString(), const Color(0xFF059669), const Color(0xFFECFDF5)),
          const SizedBox(width: 10),
          _buildStatCard('Local', pending.toString(), const Color(0xFFE11D48), const Color(0xFFFFF1F2)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSelectAll() {
    final filtered = _filteredRecords;
    setState(() {
      if (_selectedIds.length == filtered.length && filtered.isNotEmpty) {
        _selectedIds.clear();
      } else {
        for (var r in filtered) {
          if (r.localId != null) _selectedIds.add(r.localId!);
        }
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Records'),
        content: Text('Delete ${_selectedIds.length} selected record(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.deleteRecords(_selectedIds.toList());
      setState(() => _selectedIds.clear());
      _loadRecords();
      if (mounted) showToast(context, 'Records deleted', type: ToastType.success);
    }
  }

  Widget _buildSearchAndActionRow() {
    final filtered = _filteredRecords;
    final allSelected = filtered.isNotEmpty && _selectedIds.length == filtered.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSelectAll,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: allSelected ? const Color(0xFF2563EB).withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: allSelected ? const Color(0xFF2563EB).withOpacity(0.3) : Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: allSelected,
                      onChanged: (_) => _toggleSelectAll(),
                      activeColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All', 
                    style: TextStyle(
                      color: allSelected ? const Color(0xFF2563EB) : const Color(0xFF0F172A), 
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    )
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _onScanAttendee,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF059669).withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Scan Attendee', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _selectedIds.isEmpty ? null : _deleteSelected,
            child: Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: _selectedIds.isEmpty ? Colors.white : const Color(0xFFE11D48),
                borderRadius: BorderRadius.circular(12),
                border: _selectedIds.isEmpty ? Border.all(color: Colors.black.withOpacity(0.05)) : null,
              ),
              child: Icon(Icons.delete_outline_rounded, color: _selectedIds.isEmpty ? const Color(0xFF94A3B8) : Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(16),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_search_rounded, size: 48, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 24),
          const Text(
            'No attendees found',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start scanning or select a different event',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList(List<AttendanceRecord> filtered) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final record = filtered[index];
        final isSelected = _selectedIds.contains(record.localId);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: isSelected ? Border.all(color: const Color(0xFF2563EB).withOpacity(0.2), width: 1.5) : null,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Avatar/Selection
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(record.localId);
                          } else {
                            if (record.localId != null) _selectedIds.add(record.localId!);
                          }
                        });
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isSelected 
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : Center(
                              child: Text(
                                (record.attendeeName.isNotEmpty ? record.attendeeName[0] : '?').toUpperCase(),
                                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 18),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.attendeeName.isEmpty ? 'Unknown Attendee' : record.attendeeName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Text(
                                record.timeIn ?? '--:--',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.event_note_rounded, size: 12, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  record.eventName ?? 'Unassigned',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500, overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: record.synced == true ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: record.synced == true ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            record.synced == true ? 'Synced' : 'Local',
                            style: TextStyle(
                              fontSize: 11, 
                              fontWeight: FontWeight.w700,
                              color: record.synced == true ? const Color(0xFF059669) : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (record.syncError != null) ...[
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFE11D48), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          record.syncError!,
                          style: const TextStyle(color: Color(0xFFE11D48), fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
