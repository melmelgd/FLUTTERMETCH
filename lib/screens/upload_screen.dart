import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../utils/toast_helper.dart';
import '../models/attendance_record.dart';
import '../models/event_model.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedEvent = widget.initialEvent;
    _loadRecords();
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
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    final pendingCount = _records.where((r) => r.synced == false).length;
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5),
      body: Column(
        children: [
          _buildTopBar(isDark, pendingCount),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildStatsBar(isDark, filtered),
                  _buildSearchAndActionRow(isDark),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: CircularProgressIndicator(),
                        )
                      : filtered.isEmpty
                          ? _buildEmptyState(isDark)
                          : _buildAttendanceList(isDark, filtered),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark, int pendingCount) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1B2D5B),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding row
          Row(
            children: [
              Container(
                width: 38, // Reduced from 45
                height: 38, // Reduced from 45
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Padding(
                  padding: const EdgeInsets.all(4), // Added padding to shrink logo inside circle
                  child: ClipOval(
                    child: Image.asset(
                      'lib/assets/images/EM.png',
                      fit: BoxFit.contain, // Changed to contain to avoid cropping if resized
                      errorBuilder: (_, __, ___) => const Icon(Icons.location_city, color: Color(0xFF1B2D5B)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'City of Ormoc',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      'Event Management System',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _showEventPicker,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedEvent ?? 'All Events',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Row(
                      children: [
                        Text(
                          'Attendance Records',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (pendingCount > 0)
                GestureDetector(
                  onTap: _isSyncing ? null : _startSync,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        if (_isSyncing)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B2D5B)),
                          )
                        else
                          const Icon(Icons.cloud_upload_rounded, color: Color(0xFF1B2D5B), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _isSyncing ? 'Syncing...' : 'Sync ($pendingCount)',
                          style: const TextStyle(
                            color: Color(0xFF1B2D5B),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

        ],
      ),
    );
  }

  Widget _buildStatsBar(bool isDark, List<AttendanceRecord> filtered) {
    final synced = filtered.where((r) => r.synced == true).length;
    final pending = filtered.where((r) => r.synced == false).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Row(
        children: [
          _buildStatCard(isDark, filtered.length.toString(), Colors.black),
          const SizedBox(width: 12),
          _buildStatCard(isDark, synced.toString(), const Color(0xFF10B981)),
          const SizedBox(width: 12),
          _buildStatCard(isDark, pending.toString(), const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _buildStatCard(bool isDark, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.bold),
          ),
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

  Widget _buildSearchAndActionRow(bool isDark) {
    final filtered = _filteredRecords;
    final allSelected = filtered.isNotEmpty && _selectedIds.length == filtered.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.grey[400], size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _toggleSelectAll,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: allSelected ? const Color(0xFF1B2D5B).withOpacity(0.1) : (isDark ? const Color(0xFF1E293B) : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    onChanged: (_) => _toggleSelectAll(),
                    activeColor: const Color(0xFF1B2D5B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  Text(
                    'All', 
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87, 
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    )
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _selectedIds.isEmpty ? null : _deleteSelected,
            child: Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: _selectedIds.isEmpty ? Colors.grey[300] : const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
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
          Icon(Icons.group_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No attendees yet',
            style: TextStyle(color: Colors.grey[400], fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList(bool isDark, List<AttendanceRecord> filtered) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final record = filtered[index];
        final isSelected = _selectedIds.contains(record.localId);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isSelected ? Border.all(color: const Color(0xFF1B2D5B), width: 1.5) : null,
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      if (record.localId != null) _selectedIds.add(record.localId!);
                    } else {
                      _selectedIds.remove(record.localId);
                    }
                  });
                },
                activeColor: const Color(0xFF1B2D5B),
                shape: const CircleBorder(),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                child: Icon(Icons.person_rounded, color: isDark ? Colors.white70 : const Color(0xFF1B2D5B)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.attendeeName ?? 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF1B2D5B),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          record.timeIn ?? '--:--',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                        if (record.eventName != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedEvent = record.eventName),
                              child: Text(
                                record.eventName!,
                                style: TextStyle(
                                  color: isDark ? Colors.blue[300] : const Color(0xFF1B2D5B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  overflow: TextOverflow.ellipsis,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: record.synced == true 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      record.synced == true ? 'Synced' : 'Local',
                      style: TextStyle(
                        fontSize: 11, 
                        fontWeight: FontWeight.bold,
                        color: record.synced == true ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  if (record.syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Sync Error'),
                              content: Text(record.syncError!),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                              ],
                            ),
                          );
                        },
                        child: Icon(Icons.error_outline_rounded, color: Colors.red[400], size: 20),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
