// lib/screens/new_event_screen.dart
// "New Event" form screen — matches EventFlow UI screenshots

import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/toast_helper.dart';

class NewEventScreen extends StatefulWidget {
  const NewEventScreen({super.key});

  @override
  State<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends State<NewEventScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _organizerController = TextEditingController();
  final _maxAttendeesController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _category = 'Meeting';
  String _status = 'Upcoming';
  bool _isSaving = false;

  // Cover image (placeholder — integrate image_picker as needed)
  bool _hasCoverImage = false;

  final List<String> _categories = [
    'Meeting',
    'Festival',
    'Sports',
    'Concert',
    'Conference',
    'Workshop',
    'Other',
  ];

  final List<String> _statuses = [
    'Upcoming',
    'Ongoing',
    'Completed',
    'Cancelled',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _organizerController.dispose();
    _maxAttendeesController.dispose();
    super.dispose();
  }

  // ── Pickers ────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1B2D5B),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  // ── Submit ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      showToast(context, 'Please select a date', type: ToastType.warning);
      return;
    }
    setState(() => _isSaving = true);
    // TODO: call API / DatabaseService to save event
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _isSaving = false);
    showToast(context, 'Event created!', type: ToastType.success);
    Navigator.of(context).pop(true); // return true = refresh list
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCoverImage(),
                      const SizedBox(height: 20),
                      _buildSection(
                        label: 'EVENT DETAILS',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Title', required: true),
                            _buildTextField(
                              controller: _titleController,
                              hint: 'Event name',
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Title is required'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            _buildLabel('Description'),
                            _buildTextField(
                              controller: _descController,
                              hint: 'Details...',
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSection(
                        label: 'DATE & TIME',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Date', required: true),
                            _buildTappableField(
                              text: _selectedDate != null
                                  ? _formatDate(_selectedDate!)
                                  : null,
                              hint: 'mm/dd/yyyy',
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickDate,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Start Time'),
                                      _buildTappableField(
                                        text: _startTime != null
                                            ? _formatTime(_startTime!)
                                            : null,
                                        hint: '--:-- --',
                                        icon: Icons.access_time_rounded,
                                        onTap: _pickStartTime,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('End Time'),
                                      _buildTappableField(
                                        text: _endTime != null
                                            ? _formatTime(_endTime!)
                                            : null,
                                        hint: '--:-- --',
                                        icon: Icons.access_time_rounded,
                                        onTap: _pickEndTime,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSection(
                        label: 'LOCATION & ORGANIZER',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Location', required: true),
                            _buildTextField(
                              controller: _locationController,
                              hint: 'Venue',
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Location is required'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            _buildLabel('Organizer'),
                            _buildTextField(
                              controller: _organizerController,
                              hint: 'Department or office',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSection(
                        label: 'CLASSIFICATION',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Category'),
                                      _buildDropdown(
                                        value: _category,
                                        items: _categories,
                                        onChanged: (v) => setState(
                                            () => _category = v!),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Status'),
                                      _buildDropdown(
                                        value: _status,
                                        items: _statuses,
                                        onChanged: (v) =>
                                            setState(() => _status = v!),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildLabel('Max Attendees'),
                            _buildTextField(
                              controller: _maxAttendeesController,
                              hint: 'e.g. 200',
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // ── Sticky bottom button ────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined,
                      size: 18, color: Colors.white),
              label: Text(
                _isSaving ? 'Saving...' : 'Create Event',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2D5B),
                disabledBackgroundColor:
                    const Color(0xFF1B2D5B).withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B6CB7),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.40),
                      width: 1.5),
                ),
                child: const Center(
                  child: Text('D',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Back + title
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Event',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  Text('Fill in the details below',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12)),
                ],
              ),
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

  // ── Cover image ────────────────────────────────────────────────────
  Widget _buildCoverImage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('COVER IMAGE'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => showToast(context, 'Image picker — coming soon!',
              type: ToastType.info),
          child: Container(
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFDDE1EA),
                  width: 1.5,
                  style: BorderStyle.solid),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: _hasCoverImage
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_outlined,
                          size: 32,
                          color: const Color(0xFFADB5C7)),
                      const SizedBox(height: 8),
                      const Text('Tap to upload photo',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFADB5C7),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Section wrapper ────────────────────────────────────────────────
  Widget _buildSection(
      {required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
            letterSpacing: 0.8));
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          if (required)
            const Text(' *',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger)),
        ],
      ),
    );
  }

  // ── Form fields ────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: AppColors.textMain),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontSize: 14,
            color: Color(0xFFBBC0CC),
            fontWeight: FontWeight.w400),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: false,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE1EA), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF1B2D5B), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildTappableField({
    required String? text,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: const Color(0xFFDDE1EA), width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text ?? hint,
                style: TextStyle(
                    fontSize: 14,
                    color: text != null
                        ? AppColors.textMain
                        : const Color(0xFFBBC0CC),
                    fontWeight: FontWeight.w400),
              ),
            ),
            Icon(icon, size: 18, color: const Color(0xFFADB5C7)),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE1EA), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFFADB5C7), size: 20),
          style: const TextStyle(
              fontSize: 14,
              color: AppColors.textMain,
              fontWeight: FontWeight.w500),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
