import 'package:another_flushbar/another_flushbar.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:trega/core/theme/app_theme.dart';
import 'package:trega/core/widgets/motion.dart';

/// Toast severity — controls the icon, accent color and haptic.
enum TregaToastKind { success, error, info }

/// Trega's premium floating toast: dark, top-anchored, swipe-to-dismiss.
///
/// This is the app-wide replacement for raw SnackBars on user-facing
/// success / error / info feedback. Presentation only — call sites keep
/// their existing logic and just swap the display call.
///
/// When [actionLabel] is given, tapping it dismisses the toast and then
/// runs [onAction] (e.g. "View order" jumping to the tracking screen).
Future<void> showTregaToast(
  BuildContext context,
  String message, {
  TregaToastKind kind = TregaToastKind.info,
  String? title,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  switch (kind) {
    case TregaToastKind.success:
      TregaHaptics.success();
      break;
    case TregaToastKind.error:
      TregaHaptics.tap();
      break;
    case TregaToastKind.info:
      break;
  }

  final (IconData icon, Color accent) = switch (kind) {
    TregaToastKind.success =>
      (PhosphorIconsRegular.checkCircle, const Color(0xFF7BC47F)),
    TregaToastKind.error =>
      (PhosphorIconsRegular.warningCircle, const Color(0xFFE57373)),
    TregaToastKind.info =>
      (PhosphorIconsRegular.info, AppColors.accent),
  };

  late final Flushbar<bool> bar;
  bar = Flushbar<bool>(
    titleText: title == null
        ? null
        : Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.1,
            ),
          ),
    messageText: Text(
      message,
      style: const TextStyle(
        color: Color(0xFFE9DCCF),
        fontSize: 13,
        height: 1.45,
      ),
    ),
    icon: Icon(icon, color: accent, size: 26),
    shouldIconPulse: false,
    duration: duration,
    flushbarPosition: FlushbarPosition.TOP,
    flushbarStyle: FlushbarStyle.FLOATING,
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    borderRadius: BorderRadius.circular(18),
    backgroundColor: const Color(0xFF241611),
    boxShadows: const [
      BoxShadow(
        color: Color(0x4D000000),
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
    leftBarIndicatorColor: accent,
    isDismissible: true,
    dismissDirection: FlushbarDismissDirection.HORIZONTAL,
    animationDuration: const Duration(milliseconds: 350),
    forwardAnimationCurve: Curves.easeOutCubic,
    reverseAnimationCurve: Curves.easeInCubic,
    mainButton: actionLabel == null
        ? null
        : TextButton(
            onPressed: () => bar.dismiss(true),
            child: Text(
              actionLabel,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
  );

  return bar.show(context).then((acted) {
    if (acted == true) onAction?.call();
  });
}
