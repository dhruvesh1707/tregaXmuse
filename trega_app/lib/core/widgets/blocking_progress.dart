import 'package:flutter/material.dart';

/// Shows a small non-dismissible "working…" dialog the instant a server
/// round-trip starts, and returns a function that dismisses it. Call the
/// returned function in a `finally` block.
///
/// Why this exists: Cloud Functions cold-start in seconds, and a tap that
/// hits the server with no immediate feedback feels broken — the user
/// can't tell the tap registered. This makes the tap visibly land first.
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(message)),
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
      // The page went away first — nothing to dismiss.
    }
  };
}
