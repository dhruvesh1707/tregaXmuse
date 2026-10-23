import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/navigation/deep_link.dart';
import '../../../core/notifications/notification_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/screens/home_screen.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

/// Launch screen: routes based on the persisted session — home (or profile
/// setup for a fresh account) when signed in, onboarding when signed out.
///
/// Visual: the OS launch screen is now plain warm paper (the
/// flutter_native_splash config carries a color only, no image), so this
/// screen owns the whole launch moment — the logo springs in, the tagline
/// staggers in letter by letter, and three dots bounce while the session
/// restores. Rendering the logo here is safe precisely because the native
/// splash no longer shows it: the logo still appears exactly once, it just
/// moves now. (The old "double splash" came from the native logo and a
/// second, differently-sized Flutter logo stacking on top of each other.)
class SplashScreen extends ConsumerStatefulWidget {
  static const String routeName = '/';

  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  /// Entrance choreography (logo, tagline, dots, footer), ~1.5 s.
  late final AnimationController _entrance;

  /// Idle loop: the bouncing dots and the logo's subtle breathing.
  late final AnimationController _pulse;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _route();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: settle instantly, no loop.
      _entrance.value = 1;
    } else {
      _entrance.forward();
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Waits for Firebase Auth to restore the persisted session, then routes.
  ///
  /// On cold start [FirebaseAuth.currentUser] is briefly null while the SDK
  /// reads the token from disk, so this awaits the first
  /// [FirebaseAuth.authStateChanges] event instead of reading it
  /// synchronously — otherwise every restart would look "signed out" and
  /// drop the user back at onboarding. The splash stays up at least 2
  /// seconds so the entrance animation can play out.
  Future<void> _route() async {
    final auth = ref.read(firebaseAuthProvider);
    final results = await Future.wait([
      auth.authStateChanges().first,
      Future<void>.delayed(const Duration(seconds: 2)),
      // A shared-listing link can resolve after routing has started — wait for
      // the launch link (bounded) before reading the stash, or the link is
      // silently lost and the app just lands on home.
      launchDeepLink
          .timeout(const Duration(seconds: 3))
          .then<void>((_) {})
          .catchError((_) {}),
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

    // Capture the cold-start target BEFORE replacing: pushReplacementNamed
    // disposes this State synchronously, so everything after it must avoid
    // `context` and `mounted` — the old code checked `mounted` here and
    // silently dropped the target every single time.
    final pending = pendingNotificationTarget;
    pendingNotificationTarget = null;

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(next);
    if (pending != null) {
      // The splash route is gone — its context is defunct. Route on the next
      // frame through the root navigator key instead.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tregaNavigatorKey.currentState
            ?.pushNamed(pending.routeName, arguments: pending.arguments);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TregaScaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_entrance, _pulse]),
          builder: (context, _) {
            final t = _entrance.value;
            final logoP =
                Curves.easeOutCubic.transform(_interval(t, 0.0, 0.45));
            final logoScale = 0.82 + 0.18 * logoP;
            // Subtle breathing once settled — amplitude is tiny on purpose.
            final breath =
                1 + 0.012 * math.sin(_pulse.value * math.pi * 2) * logoP;
            final dotsP = _interval(t, 0.62, 0.82);
            final footerP = _interval(t, 0.74, 0.95);
            return Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: _interval(t, 0.0, 0.3),
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - logoP)),
                            child: Transform.scale(
                              scale: logoScale * breath,
                              child: Image.asset(
                                'assets/logo/trega_logo.png',
                                width: 230,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _tagline(t),
                        const SizedBox(height: 34),
                        Opacity(
                          opacity: dotsP,
                          child: _dots(),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 30,
                  child: Opacity(
                    opacity: footerP,
                    child: const Text(
                      'GAMING  ·  MOBILES  ·  FASHION  ·  LAPTOPS  ·  MORE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The tagline, revealed character by character: each glyph fades in and
  /// rises 8 px, staggered ~18 ms apart, starting at 30% of the entrance.
  Widget _tagline(double t) {
    const text = 'Buy and sell second-hand, safely.';
    final chars = text.split('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++) _tagChar(chars[i], t, i),
      ],
    );
  }

  Widget _tagChar(String ch, double t, int i) {
    final start = 0.30 + i * 0.012;
    final p = _interval(t, start, start + 0.18);
    final eased = Curves.easeOutCubic.transform(p);
    return Opacity(
      opacity: eased,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - eased)),
        child: Text(
          ch,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Three dots bouncing in sequence — brown, brown, brand yellow.
  Widget _dots() {
    final v = _pulse.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Transform.translate(
            offset: Offset(0, -_dotLift(v, i)),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == 2 ? AppColors.accent : AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ],
    );
  }

  double _dotLift(double v, int i) {
    final phase = (v - i * 0.16) % 1.0;
    final s = math.sin(phase * math.pi * 2);
    return s > 0 ? s * 5 : 0;
  }

  /// Maps [t] onto 0..1 across the [begin]..[end] slice of the timeline.
  double _interval(double t, double begin, double end) {
    return ((t - begin) / (end - begin)).clamp(0.0, 1.0).toDouble();
  }
}
