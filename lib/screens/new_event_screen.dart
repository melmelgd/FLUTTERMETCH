// lib/screens/new_event_screen.dart
// New Event screen — matches UI screenshots provided

import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/session_model.dart';
import '../services/database_service.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_header.dart';
import 'package:intl/intl.dart';

class NewEventScreen extends StatefulWidget {
  final SessionModel? session;
  final EventModel? existingEvent;
  const NewEventScreen({super.key, this.session, this.existingEvent});

  @override
  State<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends State<NewEventScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _maxAttendeesCtrl = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  String _category = 'Meeting';
  String _status = 'Upcoming';

  @override
  void initState() {
    super.initState();
    if (widget.existingEvent != null) {
      final e = widget.existingEvent!;
      _titleCtrl.text = e.eventName;
      _descCtrl.text = (e.speaker == 'none' || e.speaker == null) ? '' : e.speaker!;
      _locCtrl.text = e.eventLocation ?? '';
      _orgCtrl.text = (e.host == 'none' || e.host == null) ? '' : e.host!;
      _maxAttendeesCtrl.text = e.attendeeCount?.toString() ?? '';

      if (e.status != null && e.status!.isNotEmpty) {
        _status = e.status![0].toUpperCase() + e.status!.substring(1).toLowerCase();
      }

      if (e.eventDate != null) {
        try {
          _selectedDate = DateFormat('MMMM dd, yyyy').parse(e.eventDate!);
        } catch (_) {
          try {
            _selectedDate = DateTime.parse(e.eventDate!);
          } catch (_) {}
        }
      }

      if (e.eventTime != null && e.eventTime != 'No time') {
        try {
          final parts = e.eventTime!.split(' - ');
          final format = DateFormat.jm();
          _startTime = TimeOfDay.fromDateTime(format.parse(parts.first));
          if (parts.length > 1) {
            _endTime = TimeOfDay.fromDateTime(format.parse(parts.last));
          }
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    _orgCtrl.dispose();
    _maxAttendeesCtrl.dispose();
    super.dispose();
  }

  String get _userInitial {
    final name = widget.session?.firstName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : 'D';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCoverImageSection(),
                  const SizedBox(height: 16),
                  _buildSectionCard('EVENT DETAILS', Icons.description_outlined, const Color(0xFF3B82F6), [
                    _buildLabel('Title *'),
                    _buildTextField(hint: 'Event name', controller: _titleCtrl),
                    const SizedBox(height: 20),
                    _buildLabel('Description'),
                    _buildTextField(
                      hint: 'Add details about this event...',
                      controller: _descCtrl,
                      maxLines: 4,
                      alignLabelWithHint: true,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSectionCard('DATE & TIME', Icons.access_time_filled_rounded, const Color(0xFFF59E0B), [
                    _buildLabel('Date *'),
                    _buildDatePickerField(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Start Time'),
                              _buildTimePickerField(isStart: true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('End Time'),
                              _buildTimePickerField(isStart: false),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSectionCard('LOCATION & ORGANIZER', Icons.location_on_rounded, const Color(0xFF10B981), [
                    _buildLabel('Location *'),
                    _buildTextField(hint: 'Venue or address', controller: _locCtrl),
                    const SizedBox(height: 20),
                    _buildLabel('Organizer'),
                    _buildTextField(hint: 'Department or office', controller: _orgCtrl),
                  ]),
                  const SizedBox(height: 16),
                  _buildSectionCard('CLASSIFICATION', Icons.sell_rounded, const Color(0xFFF43F5E), [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Category'),
                              _buildDropdownField(
                                value: _category,
                                items: ['Meeting', 'Seminar', 'Workshop', 'Others'],
                                onChanged: (v) => setState(() => _category = v!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Status'),
                              _buildDropdownField(
                                value: _status,
                                items: ['Upcoming', 'Ongoing', 'Completed'],
                                onChanged: (v) => setState(() => _status = v!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Max Attendees'),
                    _buildTextField(
                      hint: 'e.g. 200',
                      controller: _maxAttendeesCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildCreateButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      userInitial: _userInitial,
      showBackButton: true,
      onNotificationTap: () {
        // Notification action if any
      },
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Event',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF0F172A), fontWeight: FontWeight.w800)),
          const Text('Fill in the details below',
              style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }



  // ── Form Components ───────────────────────────────────────────────
  Widget _buildCoverImageSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionIcon(Icons.image_outlined, const Color(0xFFA855F7)),
              const SizedBox(width: 12),
              const Text('COVER IMAGE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFF1F5F9),
                width: 1.5,
              ),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_upload_outlined,
                    color: Color(0xFFCBD5E1), size: 44),
                SizedBox(height: 12),
                Text('Tap to upload photo',
                    style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Color iconColor, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionIcon(icon, iconColor),
              const SizedBox(width: 12),
              Text(title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B))),
    );
  }

  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
    bool alignLabelWithHint = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        alignLabelWithHint: alignLabelWithHint,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFF1F5F9))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFF1F5F9))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  Widget _buildDatePickerField() {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime(2100),
        );
        if (date != null) setState(() => _selectedDate = date);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedDate == null
                  ? 'mm/dd/yyyy'
                  : '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}',
              style: TextStyle(
                color: _selectedDate == null
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.calendar_today_rounded,
                color: Color(0xFF0F172A), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerField({required bool isStart}) {
    final time = isStart ? _startTime : _endTime;
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (picked != null) {
          setState(() {
            if (isStart) {
              _startTime = picked;
            } else {
              _endTime = picked;
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              time == null ? '--:-- --' : time.format(context),
              style: TextStyle(
                color: time == null
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.access_time_rounded,
                color: Color(0xFF0F172A), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B)),
          items: items
              .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    final isEdit = widget.existingEvent != null;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _onSavePressed,
          icon: Icon(
              isEdit
                  ? Icons.save_rounded
                  : Icons.assignment_turned_in_rounded,
              size: 20),
          label: Text(isEdit ? 'Save Changes' : 'Create Event',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Future<void> _onSavePressed() async {
    final title = _titleCtrl.text.trim();
    final loc = _locCtrl.text.trim();

    if (title.isEmpty) {
      showToast(context, 'Please enter an event title', type: ToastType.error);
      return;
    }
    if (_selectedDate == null) {
      showToast(context, 'Please select an event date', type: ToastType.error);
      return;
    }
    if (loc.isEmpty) {
      showToast(context, 'Please enter a location', type: ToastType.error);
      return;
    }

    final dateStr = DateFormat('MMMM dd, yyyy').format(_selectedDate!);
    String timeStr = 'No time';
    if (_startTime != null) {
      timeStr = _startTime!.format(context);
      if (_endTime != null) {
        timeStr += ' - ${_endTime!.format(context)}';
      }
    }

    final event = EventModel(
      eventId: widget.existingEvent?.eventId,
      eventName: title,
      eventDate: dateStr,
      eventTime: timeStr,
      host: _orgCtrl.text.trim().isEmpty ? 'none' : _orgCtrl.text.trim(),
      speaker: _descCtrl.text.trim().isEmpty ? 'none' : _descCtrl.text.trim(),
      eventLocation: loc,
      status: _status.toLowerCase(),
      attendeeCount: int.tryParse(_maxAttendeesCtrl.text) ?? 0,
    );

    try {
      await DatabaseService.saveEvent(event);
      if (mounted) {
        showToast(
            context,
            widget.existingEvent != null
                ? 'Event updated successfully!'
                : 'Event created successfully!',
            type: ToastType.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Failed to save event: $e', type: ToastType.error);
      }
    }
  }
}
