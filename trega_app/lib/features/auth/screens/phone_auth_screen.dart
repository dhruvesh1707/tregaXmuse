import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../../core/firebase/auth_service.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
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

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _otpSent = false;
  bool _loading = false;
  bool _interrupted = false;
  String? _verificationId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restorePendingAttempt();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
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
        // The attempt is dead (Firebase rejected it) — don't offer a retry
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
      setState(() => _error = 'Enter the 6-digit code sent to your phone.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final result = await auth.verifyOtp(
        verificationId: _verificationId!,
        smsCode: code,
        phoneNumber: _phoneController.text.trim(),
      );
      _routeAfterSignIn(result.user.name, result.isNewUser);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'invalid-verification-code'
            ? 'Wrong code. Please check and try again.'
            : 'Verification failed (${e.code}).';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
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
      // Clear the auth stack — there's no going back to the OTP screen
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/logo/trega_logo.png', width: 120),
              const SizedBox(height: 32),
              Text(
                _otpSent ? 'Enter the OTP' : 'Welcome to Trega',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              Text(
                _otpSent
                    ? 'We sent a 6-digit code to +91 ${_phoneController.text}'
                    : 'Sign in with your phone number to buy, sell and bid.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
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
                Pinput(
                  controller: _otpController,
                  length: 6,
                  autofocus: true,
                  showCursor: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  defaultPinTheme: _pinTheme(AppColors.divider),
                  focusedPinTheme: _pinTheme(AppColors.primary),
                  submittedPinTheme:
                      _pinTheme(AppColors.primary),
                  errorPinTheme: _pinTheme(AppColors.error),
                  pinputAutovalidateMode:
                      PinputAutovalidateMode.onSubmit,
                  onChanged: (_) {
                    // A fresh edit clears a previous "wrong code" error.
                    if (_error != null) {
                      setState(() => _error = null);
                    }
                  },
                  // The code submits itself the moment the 6th digit lands.
                  onCompleted: (_) => _verifyOtp(),
                ),
              if (_interrupted && !_otpSent) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Your last verification was interrupted. Tap Send OTP to try again.',
                    style: Theme.of(context).textTheme.bodyMedium,
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
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                TregaButton(
                  label: _otpSent ? 'Verify & Continue' : 'Send OTP',
                  onPressed: _otpSent ? _verifyOtp : _sendOtp,
                ),
              if (_otpSent) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : _sendOtp,
                    child: const Text('Resend OTP'),
                  ),
                ),
                Center(
                  child: TextButton(
                    // Wrong number typed? Go back and edit it — the
                    // pending attempt is discarded.
                    onPressed: _loading
                        ? null
                        : () {
                            AuthService.clearPendingVerification();
                            setState(() {
                              _otpSent = false;
                              _verificationId = null;
                              _otpController.clear();
                              _error = null;
                            });
                          },
                    child: const Text('Change mobile number'),
                  ),
                ),
              ],
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
    );
  }
}
