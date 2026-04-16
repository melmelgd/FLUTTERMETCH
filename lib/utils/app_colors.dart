import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF020E31);
  static const primaryL = Color(0xFF04185B);
  static const accent = Color(0xFF1E3A8A);
  static const accentL = Color(0xFF1E40AF);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const bg = Color(0xFFF3F4F6);
  static const card = Color(0xFFFFFFFF);
  static const textMain = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryL],
  );

  static const attendanceHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)],
  );
}
