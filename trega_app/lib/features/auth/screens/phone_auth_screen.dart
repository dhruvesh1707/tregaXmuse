import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../../core/firebase/auth_service.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/widgets/trega_button.dart';
import '../../home/screens/home_screen.dart';
import 'profile_setup_screen.dart';

/// Phone + OTP sign-in backed by Firebase Authentication.
///
/// Firebase sends the SMS; on Android the code may be auto-retrieved
/// (instant verification). On iOS sideloads without push entitlement,
/// Firebase falls back to a reCAPTCHA check before sending the SMS.
///
/// The in-flight OTP attempt is persisted locally in two stages:
/// the phone number is saved the moment "Send OTP" is tapped (before any
/// reCAPTCHA can appear), and the verificationId is added when Firebase
/// reports `codeSent`. If the OS kills the app mid-verification (e.g. during
/// the iOS reCAPTCHA round-trip), the screen restores OTP entry when a
/// verificationId exists, or offers a one-tap retry with the number
/// prefilled when the kill happened before `codeSent`.
///
/// After sign-in, first-time users (or users without a profile name) go
/// through [ProfileSetupScreen]; returning users go straight home.
class PhoneAuthScreen extends ConsumerStatefulWidget {
  static const String routeName = '/auth/phone';

  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _otpSent = false;
  bool _loading = false;
  bool _interrupted = false;
  bool _otpSuccess = false;
  bool _otpError = false;
  String? _verificationId;
  String? _error;

  /// Wrong-code shake: 450ms, 3 oscillations, 9px amplitude, decaying.
  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void initState() {
    super.initState();
    _restorePendingAttempt();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Wrong-code feedback: shake the OTP fields and fire a heavy haptic.
  /// Motion only, the error text and retry behavior are unchanged, and
  /// the entered code is left untouched so the user keeps their place.
  void _playOtpErrorFeedback() {
    if (!mounted) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    _shakeController.forward(from: 0);
  }

  /// Restores an OTP attempt that was interrupted (e.g. the app was killed
  /// during the iOS reCAPTCHA round-trip). With a verificationId the user
  /// lands on OTP entry; without one (kill happened before `codeSent`) the
  /// phone number is prefilled and a retry banner is shown.
  Future<void> _restorePendingAttempt() async {
    final pending = await AuthService.loadPendingVerification();
    if (pending == null || !mounted) return;
    setState(() {
      _phoneController.text = pending.phoneNumber;
      if (pending.verificationId != null) {
        _otpSent = true;
        _verificationId = pending.verificationId;
      } else {
        _interrupted = true;
      }
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _interrupted = false;
      _otpError = false;
    });

    // Remember the attempt BEFORE Firebase runs: on iOS the reCAPTCHA can
    // appear immediately, and if the OS kills the app while it is up there
    // is no verificationId yet to resume with.
    await AuthService.savePendingAttempt(phoneNumber: phone);

    final auth = ref.read(authServiceProvider);
    await auth.sendOtp(
      phoneNumber: phone,
      onCodeSent: (verificationId, _) {
        // Persist before touching UI: the app may be backgrounded/killed
        // while the user completes the reCAPTCHA challenge.
        AuthService.savePendingVerification(
          verificationId: verificationId,
          phoneNumber: phone,
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _otpSent = true;
          _verificationId = verificationId;
        });
      },
      onAutoVerified: (credential) => _signInWithCredential(credential, phone),
      onError: (message) {
        // The attempt is dead (Firebase rejected it), don't offer a retry
        // banner for it on next launch.
        AuthService.clearPendingVerification();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = message;
        });
      },
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6 || _verificationId == null) {
      setState(() {
        _error = 'Enter the 6-digit code sent to your phone.';
        _otpError = true;
      });
      _playOtpErrorFeedback();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _otpError = false;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final result = await auth.verifyOtp(
        verificationId: _verificationId!,
        smsCode: code,
        phoneNumber: _phoneController.text.trim(),
      );
      // Success motion before navigating: tint the OTP fields green and
      // show the success check overlay for 800ms so the user sees the
      // code was correct, then run the existing navigation unchanged.
      // The delay is a plain Future, nothing is awaited inside setState,
      // and navigation is skipped if the widget was disposed mid-hold
      // (the route is gone, so there is nothing left to navigate from).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otpSuccess = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      _routeAfterSignIn(result.user.name, result.isNewUser);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'invalid-verification-code'
            ? 'Wrong code. Please check and try again.'
            : 'Verification failed (${e.code}).';
        _otpError = true;
      });
      _playOtpErrorFeedback();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
        _otpError = true;
      });
      _playOtpErrorFeedback();
    }
  }

  Future<void> _signInWithCredential(
    PhoneAuthCredential credential,
    String phone,
  ) async {
    try {
      final result = await ref
          .read(authServiceProvider)
          .signInWithAutoCredential(credential, phoneNumber: phone);
      _routeAfterSignIn(result.user.name, result.isNewUser);
    } catch (_) {
      // Auto-verification failed; fall through to manual OTP entry.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// New users (and returning users who never finished setup) complete
  /// their profile; everyone else goes straight home.
  void _routeAfterSignIn(String name, bool isNewUser) {
    if (!mounted) return;
    if (isNewUser || name.trim().isEmpty) {
      // Clear the auth stack, there's no going back to the OTP screen
      // once the number is verified.
      Navigator.of(context).pushNamedAndRemoveUntil(
        ProfileSetupScreen.routeName,
        (route) => false,
      );
    } else {
      _goHome();
    }
  }

  void _goHome() {
    if (!mounted) return;
    // Home becomes the root of the stack: no back button, no way back
    // into the auth screens.
    Navigator.of(context).pushNamedAndRemoveUntil(
      HomeScreen.routeName,
      (route) => false,
    );
  }

  /// iOS-style boxed OTP cell theme, tinted by state.
  PinTheme _pinTheme(Color border) {
    return PinTheme(
      width: 52,
      height: 60,
      textStyle:
          Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
      decoration: BoxDecoration(
        // NOTE: not const, Border.all has no const constructor.
        borderRadius: BorderRadius.circular(24),
        color: AppColors.surface,
        border: Border.all(color: border, width: 1.5),
        boxShadow: AppShadows.soft,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // OTP field tint follows the outcome: green once the code is
    // accepted, red after a wrong code, brand brown while entering.
    final pinBorder = _otpSuccess
        ? AppColors.success
        : _otpError
            ? AppColors.error
            : AppColors.divider;
    final pinActiveBorder = _otpSuccess
        ? AppColors.success
        : _otpError
            ? AppColors.error
            : AppColors.primary;
    return TregaScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.espresso,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.headerEspresso,
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: AppGradients.headerEspresso,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _otpSent ? 'Enter the OTP' : 'Welcome to Trega',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _otpSent
                            ? 'We sent a 6-digit code to +91 ${_phoneController.text}'
                            : 'Sign in with your phone number to buy, sell and bid.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                                color: AppColors.onEspressoSecondary),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/logo/trega_logo.png', width: 120),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!_otpSent)
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Phone number',
                                    prefixText: '+91 ',
                                    hintText: '98765 43210',
                                  ),
                                )
                              else
                                AnimatedBuilder(
                                  animation: _shakeController,
                                  builder: (context, child) {
                                    final t = _shakeController.value;
                                    final offset = math.sin(
                                              t * math.pi * 2 * 3,
                                            ) *
                                            9 *
                                            (1 - t);
                                    return Transform.translate(
                                      offset: Offset(offset, 0),
                                      child: child,
                                    );
                                  },
                                  child: IgnorePointer(
                                    ignoring: _otpSuccess,
                                    child: Pinput(
                                      controller: _otpController,
                                      length: 6,
                                      autofocus: true,
                                      showCursor: true,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      defaultPinTheme: _pinTheme(pinBorder),
                                      focusedPinTheme:
                                          _pinTheme(pinActiveBorder),
                                      submittedPinTheme:
                                          _pinTheme(pinActiveBorder),
                                      errorPinTheme:
                                          _pinTheme(AppColors.error),
                                      pinputAutovalidateMode:
                                          PinputAutovalidateMode.onSubmit,
                                      onChanged: (_) {
                                        // A fresh edit clears a previous "wrong code" error.
                                        if (_error != null || _otpError) {
                                          setState(() {
                                            _error = null;
                                            _otpError = false;
                                          });
                                        }
                                      },
                                      // The code submits itself the moment the 6th digit lands.
                                      onCompleted: (_) => _verifyOtp(),
                                    ),
                                  ),
                                ),
                              if (_interrupted && !_otpSent) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSoft,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                        color: AppColors.divider),
                                  ),
                                  child: Text(
                                    'Your last verification was interrupted. Tap Send OTP to try again.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.error),
                                ),
                              ],
                              const SizedBox(height: 16),
                              // The button stays mounted while busy (label swaps and it
                              // disables) so the layout doesn't jump when the spinner
                              // would otherwise replace it.
                              TregaButton(
                                label: _loading
                                    ? (_otpSent ? 'Verifying…' : 'Sending…')
                                    : (_otpSent
                                        ? 'Verify & Continue'
                                        : 'Send OTP'),
                                onPressed: (_loading || _otpSuccess)
                                    ? null
                                    : (_otpSent ? _verifyOtp : _sendOtp),
                              ),
                              if (_otpSent) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton(
                                      onPressed: (_loading || _otpSuccess)
                                          ? null
                                          : _sendOtp,
                                      child: const Text('Resend OTP'),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton(
                                      // Wrong number typed? Go back and edit it, the
                                      // pending attempt is discarded.
                                      onPressed: (_loading || _otpSuccess)
                                          ? null
                                          : () {
                                              AuthService
                                                  .clearPendingVerification();
                                              setState(() {
                                                _otpSent = false;
                                                _verificationId = null;
                                                _otpController.clear();
                                                _error = null;
                                                _otpError = false;
                                              });
                                            },
                                      child: const Text(
                                          'Change mobile number'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'By continuing you agree to our Terms of Service and Privacy Policy.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_otpSuccess)
              Positioned.fill(
                child: Container(
                  color: AppColors.background,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SuccessCheck(),
                      const SizedBox(height: 16),
                      Text(
                        'Code verified',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Taking you in...',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
