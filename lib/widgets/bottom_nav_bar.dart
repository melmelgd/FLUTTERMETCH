// lib/widgets/bottom_nav_bar.dart
// Pill-shaped bottom nav with a floating center FAB

import 'package:flutter/material.dart';

class AppBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onFabPressed;

  const AppBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
    required this.onFabPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // ── Pill bar ──────────────────────────────────────────
            Positioned(
              bottom: 12,
              left: 20,
              right: 20,
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: const Color(0xFFDDE1EA),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Left side: Home + Events
                    Expanded(child: _buildNavItem(0, Icons.space_dashboard_outlined)),
                    Expanded(child: _buildNavItem(1, Icons.calendar_today_outlined)),
                    // Center gap for FAB
                    const SizedBox(width: 72),
                    // Right side: QR + Settings
                    Expanded(child: _buildNavItem(2, Icons.qr_code_2_rounded)),
                    Expanded(child: _buildNavItem(3, Icons.settings_outlined)),
                  ],
                ),
              ),
            ),

            // ── Floating center FAB ────────────────────────────────
            Positioned(
              bottom: 28,
              child: GestureDetector(
                onTap: onFabPressed,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1B2D5B), // dark navy
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final selected = index == selectedIndex;
    return InkWell(
      onTap: () => onTabChanged(index),
      borderRadius: BorderRadius.circular(40),
      child: Center(
        child: Icon(
          icon,
          size: 24,
          color: selected
              ? const Color(0xFF1B2D5B)
              : const Color(0xFFADB5C7),
        ),
      ),
    );
  }
}
