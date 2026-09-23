import 'dart:async';

import 'package:flutter/material.dart';

import 'onboarding_screen.dart';

/// Launch screen: shows the Trega logo, then routes to onboarding
/// (or home when a valid session exists).
class SplashScreen extends StatefulWidget {
  static const String routeName = '/';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // TODO(auth): check persisted session; if logged in, go to HomeScreen.
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacementNamed(OnboardingScreen.routeName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 64),
          child: Image.asset(
            'assets/logo/trega_logo.png',
            // TODO: generate launcher icons + splash via flutter_native_splash
            // and flutter_launcher_icons using this asset.
          ),
        ),
      ),
    );
  }
}
