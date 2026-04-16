import 'package:flutter/material.dart';
import 'app_colors.dart';

enum ToastType { success, warning, error, info }

void showToast(BuildContext context, String message,
    {ToastType type = ToastType.success}) {
  final Color bg;
  switch (type) {
    case ToastType.success:
      bg = AppColors.success;
      break;
    case ToastType.warning:
      bg = AppColors.warning;
      break;
    case ToastType.error:
      bg = AppColors.danger;
      break;
    case ToastType.info:
      bg = const Color(0xFF1E293B);
      break;
  }
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
    backgroundColor: bg,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: const Duration(seconds: 3),
  ));
}
