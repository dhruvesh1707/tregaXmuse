import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/notifications/notification_router.dart';
import '../../home/screens/home_screen.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

/// Launch screen: routes based on the persisted session — home (or profile
/// setup for a fresh account) when signed in, onboarding when signed out.
///
/// The visual is pure white with NO logo. The OS launch screen
/// (flutter_native_splash) already shows the logo; rendering it again here
/// at a different size reads as a "double" splash. The logo appears exactly
/// once (native), then this white screen holds while the session restores,
/// then the app fades in.
class SplashScreen extends ConsumerStatefulWidget {
  static const String routeName = '/';

  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  /// Waits for Firebase Auth to restore the persisted session, then routes.
  ///
  /// On cold start [FirebaseAuth.currentUser] is briefly null while the SDK
  /// reads the token from disk, so this awaits the first
  /// [FirebaseAuth.authStateChanges] event instead of reading it
  /// synchronously — otherwise every restart would look "signed out" and
  /// drop the user back at onboarding. The splash stays up at least 2
  /// seconds for the logo animation.
  Future<void> _route() async {
    final auth = ref.read(firebaseAuthProvider);
    final results = await Future.wait([
      auth.authStateChanges().first,
      Future<void>.delayed(const Duration(seconds: 2)),
    ]);
    if (!mounted) return;
    final user = results[0] as User?;

    String next;
    if (user == null) {
      next = OnboardingScreen.routeName;
    } else {
      // Signed in — mirror the post-OTP routing: a missing display name
      // means the profile was never completed.
      final profile =
          await ref.read(firestoreServiceProvider).getUser(user.uid);
      if (!mounted) return;
      next = (profile == null || profile.name.trim().isEmpty)
          ? ProfileSetupScreen.routeName
          : HomeScreen.routeName;
    }

    Navigator.of(context).pushReplacementNamed(next);
    // Cold start from a tapped push notification: open what it was about.
    final pending = pendingNotificationTarget;
    pendingNotificationTarget = null;
    if (pending != null && mounted) {
      openNotificationTarget(context, pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pure white, no logo — the native launch screen already showed it.
    // Showing the logo again here at a different size is what produced the
    // "double splash" (native logo -> Flutter logo jump).
    return const Scaffold(
      backgroundColor: Color(0xFFFFFFFF),
    );
  }
}
