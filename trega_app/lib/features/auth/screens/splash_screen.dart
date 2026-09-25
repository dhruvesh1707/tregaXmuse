import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/notifications/notification_router.dart';
import '../../home/screens/home_screen.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

/// Launch screen: the Trega logo breathes gently, then routes based on the
/// persisted session — home (or profile setup for a fresh account) when
/// signed in, onboarding when signed out.
class SplashScreen extends ConsumerStatefulWidget {
  static const String routeName = '/';

  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.06)
      .animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

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
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 64),
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset('assets/logo/trega_logo.png'),
          ),
        ),
      ),
    );
  }
}
