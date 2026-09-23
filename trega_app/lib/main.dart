import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Local cache: Firestore keeps query results on disk and serves them
  // instantly on cold start / offline, then syncs with the server in the
  // background. Must be set before any Firestore read happens.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: TregaApp()));
}
