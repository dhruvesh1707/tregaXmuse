import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../network/connectivity_service.dart';
import 'error_state.dart';

/// Full-screen "you're offline" state: the same visual language as
/// [TregaErrorState] (fade-slide entrance, icon medallion, retry button)
/// with offline-specific copy.
///
/// Never construct this directly in a load-failure branch — use
/// [errorStateFor] so non-network errors keep the screen's own message.
class NoInternetState extends StatelessWidget {
  final VoidCallback onRetry;

  const NoInternetState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return TregaErrorState(
      title: "You're offline",
      subtitle: 'Check your internet connection and try again.',
      icon: PhosphorIconsRegular.cloudSlash,
      onRetry: onRetry,
    );
  }
}

/// Picks the right failure widget for a load error: [NoInternetState]
/// when [error] looks like a connectivity failure, otherwise a
/// [TregaErrorState] with the screen's own [title].
///
/// Drop-in replacement for
/// `error: (_, __) => TregaErrorState(title: ..., onRetry: ...)` —
/// just capture the error and pass it in:
/// `error: (e, _) => errorStateFor(e, title: ..., onRetry: ...)`.
Widget errorStateFor(
  Object error, {
    required String title,
    required VoidCallback onRetry,
  }) {
    if (isNetworkError(error)) return NoInternetState(onRetry: onRetry);
    return TregaErrorState(title: title, onRetry: onRetry);
  }
