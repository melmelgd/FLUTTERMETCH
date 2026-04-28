// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import '../models/session_model.dart';
import '../services/session_service.dart';
import '../services/database_service.dart';
import '../main.dart';
import 'privacy_policy_screen.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  final SessionModel? session;

  const SettingsScreen({super.key, this.session});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUpdateCount();
  }

  Future<void> _loadUpdateCount() async {
    try {
      final pending = await DatabaseService.getPendingRecords();
      final events = await DatabaseService.getCachedEvents();
      if (mounted) {
        setState(() {
          _updateCount = pending.length + events.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading update count: $e');
    }
  }

  String get _userInitial {
    final name = widget.session?.firstName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : 'D';
  }

  String get _fullName => widget.session?.firstName ?? 'david';
  String get _email => widget.session?.email ?? '${_fullName.toLowerCase()}38700988@gmail.com';
  String get _role => widget.session?.accountType ?? 'Admin';

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
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

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileCard(isDark),
                  const SizedBox(height: 32),
                  _buildSectionLabel('PREFERENCES'),
                  const SizedBox(height: 12),
                  _buildPreferenceGroup(isDark, [
                    _buildToggleItem(
                      isDark: isDark,
                      icon: Icons.notifications_none_rounded,
                      iconColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF7ED),
                      iconFgColor: const Color(0xFFF59E0B),
                      label: 'Notifications',
                      value: _notificationsEnabled,
                      onChanged: (v) => setState(() => _notificationsEnabled = v),
                    ),
                    _buildToggleItem(
                      isDark: isDark,
                      icon: isDark ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                      iconColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF7ED),
                      iconFgColor: const Color(0xFFF59E0B),
                      label: 'Dark Mode',
                      value: isDark,
                      onChanged: (v) => themeService.toggleTheme(v),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionLabel('ABOUT'),
                  const SizedBox(height: 12),
                  _buildPreferenceGroup(isDark, [
                    _buildNavItem(
                      isDark: isDark,
                      icon: Icons.shield_outlined,
                      iconColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                      iconFgColor: const Color(0xFF3B82F6),
                      label: 'Privacy Policy',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                        );
                      },
                    ),
                    _buildAppVersionItem(isDark),
                  ]),
                  const SizedBox(height: 32),
                  _buildSignOutButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1B2D5B),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.location_city, color: Color(0xFF1B2D5B), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('City of Ormoc', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('EVENT MANAGEMENT', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.5)),
                  ],
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 18),
                  ),
                  if (_notificationsEnabled && _updateCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$_updateCount',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: Center(child: Text(_userInitial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const Text('Manage your preferences', style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildProfileCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(color: Color(0xFF1B2D5B), shape: BoxShape.circle),
            child: Center(child: Text(_userInitial, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fullName,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1B2D5B))),
                Text(_email, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(_role,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1.2)),
    );
  }

  Widget _buildPreferenceGroup(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.1 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleItem({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required Color iconFgColor,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconFgColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1B2D5B))),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF1B2D5B),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required Color iconFgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconFgColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1B2D5B))),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAppVersionItem(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: isDark ? const Color(0xFF064E3B) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.info_outline, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('App Version',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1B2D5B))),
                const Text('v1.0.0 — LGU Ormoc', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton() {
    return InkWell(
      onTap: _logout,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
            SizedBox(width: 12),
            Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
