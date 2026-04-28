// lib/widgets/bottom_nav_bar.dart
// Updated Pill-shaped bottom nav with elevated center FAB — matches UI screenshot

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
    return Container(
      height: 110,
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // ── Pill bar ──────────────────────────────────────────
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: const Color(0xFFD1D5DB),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Left side
                  Expanded(child: _buildNavItem(0, Icons.grid_view_rounded, 'Dashboard')),
                  Expanded(child: _buildNavItem(1, Icons.calendar_month_outlined, 'Events')),
                  // Center gap for FAB
                  const SizedBox(width: 80),
                  // Right side
                  Expanded(child: _buildNavItem(2, Icons.how_to_reg_outlined, 'Attendance')),
                  Expanded(child: _buildNavItem(3, Icons.settings_outlined, 'Settings')),
                ],
              ),
            ),
          ),

          // ── Floating elevated center FAB ────────────────────────
          Positioned(
            bottom: 45,
            child: GestureDetector(
              onTap: onFabPressed,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B2D5B), // dark navy
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final selected = index == selectedIndex;
    final color = selected ? const Color(0xFF1B2D5B) : const Color(0xFF1F2937);
    return InkWell(
      onTap: () => onTabChanged(index),
      borderRadius: BorderRadius.circular(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
