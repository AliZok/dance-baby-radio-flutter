import 'package:flutter/material.dart';

/// Lightweight toast matching Nuxt notification stack feel.
class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xE6222830)
            : const Color(0xE608282C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isError
                ? const Color(0xFFFF6B8A).withOpacity(0.45)
                : const Color(0xFF84F3FF).withOpacity(0.28),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(
                title,
                style: TextStyle(
                  color: isError ? const Color(0xFFFF8DA3) : const Color(0xFF84F3FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
        duration: Duration(milliseconds: isError ? 4500 : 2800),
      ),
    );
  }

  static void success(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title);
  }

  static void error(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title, isError: true);
  }

  static void info(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title);
  }
}
