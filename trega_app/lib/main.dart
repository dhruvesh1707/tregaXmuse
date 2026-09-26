import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/notifications/notification_router.dart';
import 'core/observability/observability_config.dart';
import 'firebase_options.dart';

/// Entry point for the Trega marketplace app.
///
/// Backend: Firebase project `tregaxmuse`.
/// Run `flutterfire configure --project=tregaxmuse` once on your machine to
/// generate the real `lib/firebase_options.dart` before first run.
///
/// Handles notification taps that arrive while the app is terminated.
/// Foreground/background presentation is left to the OS defaults in v1.
///
/// Observability: Sentry (crash reporting) and Datadog (RUM + logs) are
/// wired in but inert until their `--dart-define` flags are passed — see
/// [ObservabilityConfig]. Builds without keys behave exactly as before.
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

DatadogSite _datadogSite(String name) {
  switch (name) {
    case 'eu1':
      return DatadogSite.eu1;
    case 'us3':
      return DatadogSite.us3;
    case 'us5':
      return DatadogSite.us5;
    case 'ap1':
      return DatadogSite.ap1;
    case 'ap2':
      return DatadogSite.ap2;
    case 'us1':
    default:
      return DatadogSite.us1;
  }
}

/// Datadog RUM + log collection. Native crash reporting to Datadog is
/// enabled; Dart/Flutter errors are owned by Sentry when it is configured,
/// so the two don't fight over the error handlers.
Future<void> _initDatadog() async {
  final configuration = DatadogConfiguration(
    clientToken: ObservabilityConfig.datadogClientToken,
    env: ObservabilityConfig.datadogEnv,
    site: _datadogSite(ObservabilityConfig.datadogSite),
    nativeCrashReportEnabled: true,
    loggingConfiguration: DatadogLoggingConfiguration(),
    rumConfiguration: DatadogRumConfiguration(
      applicationId: ObservabilityConfig.datadogApplicationId,
    ),
  );
  await DatadogSdk.instance.initialize(configuration);
}

/// Full app boot: framework, Firebase, notifications, Datadog, then runApp.
/// Wrapped by Sentry in [main] so even boot-time failures are reported.
Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // iOS: show the banner + badge + sound even when the app is in the
  // foreground. Without this, foreground pushes are silently swallowed.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

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

  if (ObservabilityConfig.datadogEnabled) {
    await _initDatadog();
  }

  runApp(const ProviderScope(child: TregaApp()));
}

Future<void> main() async {
  if (ObservabilityConfig.sentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = ObservabilityConfig.sentryDsn;
        options.environment = kReleaseMode ? 'production' : 'development';
        // 20% of transactions: enough performance signal without the
        // volume bill. Raise temporarily when hunting a specific issue.
        options.tracesSampleRate = 0.2;
      },
      appRunner: _boot,
    );
  } else {
    await _boot();
  }
}
