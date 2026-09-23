import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

/// Entry point for the Trega marketplace app.
///
/// Backend: Firebase project `tregaxmuse`.
/// Run `flutterfire configure --project=tregaxmuse` once on your machine to
/// generate the real `lib/firebase_options.dart` before first run.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProviderScope(child: TregaApp()));
}
