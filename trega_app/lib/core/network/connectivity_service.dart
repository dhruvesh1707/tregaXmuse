import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// App-wide connectivity monitor.
///
/// A singleton holding a [ValueNotifier] so any widget can react to
/// connectivity changes without a [BuildContext]. Initialized once in
/// `main()` before `runApp`; the floating offline pill in [TregaScaffold]
/// and every screen's error branch read from here.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  /// Current connectivity state. Starts `true` until the first platform
  /// check completes inside [init].
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> init() async {
    final results = await Connectivity().checkConnectivity();
    isOnline.value = _isOnline(results);
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      isOnline.value = _isOnline(results);
    });
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      !results.contains(ConnectivityResult.none);

  void dispose() {
    _sub?.cancel();
    isOnline.dispose();
  }
}

/// True when [error] looks like a connectivity failure rather than an
/// app/logic error: socket errors, Firebase "unavailable", timeouts.
///
/// Use it in every load-failure branch (via `errorStateFor`) so a dead
/// connection reads as "you're offline", not a generic error.
bool isNetworkError(Object? error) {
  if (error == null) return false;
  if (error is SocketException) return true;
  if (error is FirebaseException) {
    return error.code == 'unavailable' ||
        error.code == 'deadline-exceeded' ||
        error.code == 'resource-exhausted';
  }
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection aborted') ||
      s.contains('connection timed out') ||
      s.contains('connection refused');
}
