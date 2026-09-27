import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

/// The app's root navigator key (MaterialApp's key).
///
/// Lives here — not in app.dart — so early-startup code like the splash
/// screen can route through it without importing the app widget (which would
/// be a circular import: app.dart imports the splash screen).
final tregaNavigatorKey = GlobalKey<NavigatorState>();

/// Shared AppLinks instance, kept alive for the app's lifetime so the
/// warm-link stream can never go quiet from the instance being collected.
final AppLinks tregaAppLinks = AppLinks();

/// Completes with the link that launched the app, or null on a normal launch.
///
/// Assigned in main() before runApp(). The splash screen awaits this (with a
/// timeout) before consuming the stashed cold-start target: without the wait,
/// a slow platform channel can deliver the link after the splash already read
/// the (still empty) stash, and the link is silently lost.
late final Future<Uri?> launchDeepLink;
