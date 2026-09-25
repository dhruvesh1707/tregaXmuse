import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/notifications/notification_router.dart';
import 'firebase_options.dart';

/// Entry point for the Trega marketplace app.
///
/// Backend: Firebase project `tregaxmuse`.
/// Run `flutterfire configure --project=tregaxmuse` once on your machine to
/// generate the real `lib/firebase_options.dart` before first run.
///
/// Handles notification taps that arrive while the app is terminated.
/// Foreground/background presentation is left to the OS defaults in v1.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

/// Routes a tapped push notification to the screen it is about.
void _routePushMessage(RemoteMessage message) {
  final target = targetForNotification(
    type: message.data['type']?.toString() ?? 'system',
    data: message.data,
  );
  if (target == null) return;
  tregaNavigatorKey.currentState
      ?.pushNamed(target.routeName, arguments: target.arguments);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Tapping a push while the app is backgrounded: the navigator is already
  // up, so route straight away.
  FirebaseMessaging.onMessageOpenedApp.listen(_routePushMessage);
  // Tapping a push while the app is terminated: stash the target — the
  // splash screen pushes it once initial routing settles.
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message == null) return;
    pendingNotificationTarget = targetForNotification(
      type: message.data['type']?.toString() ?? 'system',
      data: message.data,
    );
  });

  // Local cache: Firestore keeps query results on disk and serves them
  // instantly on cold start / offline, then syncs with the server in the
  // background. Must be set before any Firestore read happens.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: TregaApp()));
}
