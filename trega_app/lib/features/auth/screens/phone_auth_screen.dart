import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/trega_button.dart';
import '../../home/screens/home_screen.dart';

/// Phone + OTP sign-in backed by Firebase Authentication.
///
/// Firebase sends the SMS; on Android the code may be auto-retrieved
/// (instant verification). On web, Firebase uses invisible reCAPTCHA — the
/// site domain must be allow-listed in the Firebase console
/// (Authentication → Settings → Authorized domains).
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
  String? _verificationId;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
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
    });

    final auth = ref.read(authServiceProvider);
    await auth.sendOtp(
      phoneNumber: phone,
      onCodeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _otpSent = true;
          _verificationId = verificationId;
        });
      },
      onAutoVerified: (credential) => _signInWithCredential(credential, phone),
      onError: (message) {
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
      await auth.verifyOtp(
        verificationId: _verificationId!,
        smsCode: code,
        phoneNumber: _phoneController.text.trim(),
      );
      _goHome();
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
      await ref
          .read(authServiceProvider)
          .signInWithAutoCredential(credential, phoneNumber: phone);
      _goHome();
    } catch (_) {
      // Auto-verification failed; fall through to manual OTP entry.
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(HomeScreen.routeName);
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
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    hintText: '6-digit code',
                  ),
                ),
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
