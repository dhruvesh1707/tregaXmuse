import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows a small non-dismissible solid espresso "working…" dialog the instant
/// a server round-trip starts, and returns a function that dismisses it.
/// Call the returned function in a `finally` block.
///
/// Why this exists: Cloud Functions cold-start in seconds, and a tap that
/// hits the server with no immediate feedback feels broken, the user
/// can't tell the tap registered. This makes the tap visibly land first.
///
/// Solid [AppColors.espresso] panel, no shadow.
Future<void> Function() showBlockingProgress(
  BuildContext context,
  String message,
) {
  var dismissed = false;
  // ignore: discarded_futures
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          decoration: BoxDecoration(
            color: AppColors.espresso,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return () async {
    if (dismissed) return;
    dismissed = true;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      // The page went away first, nothing to dismiss.
    }
  };
}
