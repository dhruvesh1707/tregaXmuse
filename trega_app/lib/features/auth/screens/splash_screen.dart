import 'dart:async';

import 'package:flutter/material.dart';

import 'onboarding_screen.dart';

/// Launch screen: the Trega logo breathes gently, then routes to onboarding
/// (or home when a valid session exists).
class SplashScreen extends StatefulWidget {
  static const String routeName = '/';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
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
    // TODO(auth): check persisted session; if logged in, go to HomeScreen.
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(OnboardingScreen.routeName);
    });
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
