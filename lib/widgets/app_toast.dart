import 'package:flutter/material.dart';

/// Lightweight toast matching Nuxt notification stack feel.
///
/// Auto-dismisses after a few seconds. Tap once to keep it on screen;
/// tap again to dismiss.
class AppToast {
  static const Duration _autoDismiss = Duration(milliseconds: 3500);
  static const Duration _errorDismiss = Duration(milliseconds: 4000);
  static const Duration _pinnedDuration = Duration(days: 1);

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    bool isError = false,
    bool pinned = false,
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
        duration: pinned
            ? _pinnedDuration
            : (isError ? _errorDismiss : _autoDismiss),
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (pinned) {
              messenger.hideCurrentSnackBar();
              return;
            }
            show(
              context,
              message: message,
              title: title,
              isError: isError,
              pinned: true,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Text(
                  title,
                  style: TextStyle(
                    color: isError
                        ? const Color(0xFFFF8DA3)
                        : const Color(0xFF84F3FF),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (pinned) ...[
                const SizedBox(height: 4),
                Text(
                  'Tap to dismiss',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
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
