import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows a small non-dismissible dark-glass "working…" dialog the instant
/// a server round-trip starts, and returns a function that dismisses it.
/// Call the returned function in a `finally` block.
///
/// Why this exists: Cloud Functions cold-start in seconds, and a tap that
/// hits the server with no immediate feedback feels broken — the user
/// can't tell the tap registered. This makes the tap visibly land first.
///
/// Dark glass: espresso at 0.78 alpha + blur 16 + hairline white-at-0.14
/// border, no heavy shadow.
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              decoration: BoxDecoration(
                color: AppColors.espresso.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
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
      ),
    ),
  );
  return () async {
    if (dismissed) return;
    dismissed = true;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      // The page went away first — nothing to dismiss.
    }
  };
}
