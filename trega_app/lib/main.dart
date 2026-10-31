import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/navigation/deep_link.dart';
import 'core/network/connectivity_service.dart';
import 'core/notifications/notification_router.dart';
import 'features/listing_detail/screens/listing_detail_screen.dart';
import 'firebase_options.dart';

/// Entry point for the Trega marketplace app.
///
/// Backend: Firebase project `tregaxmuse`.
/// Run `flutterfire configure --project=tregaxmuse` once on your machine to
/// generate the real `lib/firebase_options.dart` before first run.
///
/// Handles notification taps that arrive while the app is terminated.
/// Background/killed presentation is the OS's (FCM tray); foreground
/// pushes on Android are shown via flutter_local_notifications below.
///
/// Observability: Firebase Crashlytics (crash reporting) + Firebase
/// Performance Monitoring (app-start, screen & network traces) ride on the
/// existing tregaxmuse project — no keys, no extra accounts, no build flags.
/// Crash collection is disabled in debug builds.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

/// Local notifications — Android foreground display. FCM presents pushes
/// itself when the app is backgrounded or killed, but a push that arrives
/// while the app is OPEN is handed to Dart and never shown; this plugin
/// turns it into a banner. The channel id must match the manifest's
/// default_notification_channel_id and the backend's FCM channelId.
const String _alertsChannelId = 'trega_alerts';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Shows a foreground push as a local notification. The payload is the
/// FCM data map as JSON, so a tap routes exactly like a tray-push tap.
Future<void> _showForegroundPush(RemoteMessage message) async {
  // iOS presents foreground pushes itself (see the presentation options
  // in main); only Android needs the local-notification path.
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final notification = message.notification;
  if (notification == null) return;
  await _localNotifications.show(
    message.hashCode,
    notification.title,
    notification.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _alertsChannelId,
        'Trega alerts',
        channelDescription:
            'Offers, order updates and listing alerts from Trega.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

/// A tap on a foreground-shown local notification. The app is alive, so
/// route immediately through the same resolver tray taps use.
void _onLocalNotificationTap(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final target = targetForNotification(
    type: data['type']?.toString() ?? 'system',
    data: data,
  );
  if (target == null) return;
  tregaNavigatorKey.currentState
      ?.pushNamed(target.routeName, arguments: target.arguments);
}

/// Creates the Android alerts channel (high importance = banner + sound)
/// and wires the foreground-display path. Called once at startup; the
/// platform-specific pieces are no-ops on iOS.
Future<void> _initLocalNotifications() async {
  await _localNotifications.initialize(
    InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _onLocalNotificationTap,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        AndroidNotificationChannel(
          _alertsChannelId,
          'Trega alerts',
          description: 'Offers, order updates and listing alerts from Trega.',
          importance: Importance.high,
        ),
      );
  FirebaseMessaging.onMessage.listen(_showForegroundPush);
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

/// Deep links from shared listings:
///   - trega://listing/<id> (custom scheme), and
///   - https://tregaxmuse.web.app/l/<id> (Android App Links — the manifest
///     declares autoVerify for this host/path, and assetlinks.json proves
///     ownership).
/// Cold start: stashed for the splash screen (navigator isn't up yet) —
/// same mechanism as a tapped push on a terminated app.
/// Warm (app already running): routed immediately like a tapped push.
void _handleDeepLink(Uri uri, {required bool cold}) {
  String? id;
  if (uri.scheme == 'trega' && uri.host == 'listing') {
    id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (uri.scheme == 'https' &&
      uri.host == 'tregaxmuse.web.app' &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments.first == 'l') {
    id = uri.pathSegments[1];
  }
  if (id == null || id.isEmpty) return;
  const route = ListingDetailScreen.routeName;
  if (cold) {
    pendingNotificationTarget =
        NotificationTarget(route, ListingDetailArgs(listingId: id));
  } else {
    tregaNavigatorKey.currentState
        ?.pushNamed(route, arguments: ListingDetailArgs(listingId: id));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Crashlytics: every Flutter framework error...
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  // ...and every uncaught async error outside the framework.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  // No crash noise from debug builds; release/profile report normally.
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // iOS: show the banner + badge + sound even when the app is in the
  // foreground. Without this, foreground pushes are silently swallowed.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Android: create the alerts channel + show foreground pushes (FCM
  // never displays a push while the app is open). No-op pieces on iOS.
  await _initLocalNotifications();

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

  // Shared-listing deep links (trega://listing/<id>,
  // https://tregaxmuse.web.app/l/<id>).
  //
  // The launch link is exposed for the splash screen: it awaits it (bounded)
  // before consuming the stashed cold-start target, so a slow platform
  // channel can't slip the link in after the splash already read the empty
  // stash and silently drop it.
  launchDeepLink = tregaAppLinks.getInitialLink().then((uri) {
    if (uri != null) _handleDeepLink(uri, cold: true);
    return uri;
  }).catchError((_) => null);
  tregaAppLinks.uriLinkStream.listen(
    (uri) => _handleDeepLink(uri, cold: false),
    onError: (_) {},
  );

  // Local cache: Firestore keeps query results on disk and serves them
  // instantly on cold start / offline, then syncs with the server in the
  // background. Must be set before any Firestore read happens.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Connectivity: start monitoring before the first screen builds, so the
  // offline pill and no-internet error states read the correct state.
  await ConnectivityService.instance.init();

  runApp(const ProviderScope(child: TregaApp()));
}
