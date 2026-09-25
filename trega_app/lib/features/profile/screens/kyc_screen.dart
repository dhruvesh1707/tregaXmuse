import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/functions_service.dart';
import '../../../core/models/kyc_verification.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_toast.dart';

/// Aadhaar KYC with OTP (BulkPe).
///
/// Flow: read the consent notice and tick the consent checkbox → enter
/// 12-digit Aadhaar → [requestAadhaarOtp] sends an OTP to the Aadhaar-linked
/// mobile → enter OTP → [verifyAadhaarOtp] completes verification. The
/// Aadhaar number is never stored anywhere — it travels only to our Cloud
/// Function over TLS, and the consent timestamp is recorded when the OTP
/// is requested.
///
/// Progress is watched from `kycVerifications/{uid}`: `otp_sent` →
/// `verified` | `failed`. Verified sellers get the badge on their profile.
class KycScreen extends ConsumerStatefulWidget {
  static const String routeName = '/kyc';

  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  final _aadhaarController = TextEditingController();
  final _otpController = TextEditingController();
  String? _refId;
  bool _busy = false;
  bool _consented = false;
  String? _error;
  Timer? _cooldownTimer;
  int _resendIn = 0; // seconds until the Resend OTP button re-enables

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _aadhaarController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (!_consented) {
      setState(() {
        _error = 'Please tick the consent checkbox to continue.';
      });
      return;
    }
    final aadhaar = _aadhaarController.text.replaceAll(RegExp(r'\D'), '');
    if (aadhaar.length != 12) {
      setState(() => _error = 'Enter your 12-digit Aadhaar number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final refId = await ref
          .read(functionsServiceProvider)
          .requestAadhaarOtp(aadhaar);
      if (!mounted) return;
      setState(() {
        _refId = refId;
        _busy = false;
      });
      _startCooldown();
      await showTregaToast(
        context,
        'Enter the 6-digit code sent to your Aadhaar-linked mobile number.',
        title: 'OTP sent',
        kind: TregaToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Surface the server's real message (invalid number, throttled,
        // provider outage, ...) instead of a generic failure.
        _error = functionsErrorMessage(e,
            fallback: 'Could not send the OTP. Please try again.',);
      });
    }
  }

  /// Resend issues a fresh OTP for the same Aadhaar number. The server
  /// throttles OTP requests to one per 60 seconds, so the button runs a
  /// matching client-side countdown instead of failing silently.
  Future<void> _resendOtp() async {
    _otpController.clear();
    await _requestOtp();
  }

  void _startCooldown() {
    _stopCooldown();
    setState(() => _resendIn = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendIn--;
        if (_resendIn <= 0) {
          _resendIn = 0;
          t.cancel();
        }
      });
    });
  }

  void _stopCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _resendIn = 0;
  }

  String get _resendLabel {
    if (_resendIn <= 0) return 'Resend OTP';
    final m = _resendIn ~/ 60;
    final s = (_resendIn % 60).toString().padLeft(2, '0');
    return 'Resend OTP in $m:$s';
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Enter the OTP you received.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(functionsServiceProvider)
          .verifyAadhaarOtp(_refId!, otp);
      if (!mounted) return;
      setState(() => _busy = false);
      // The kycVerifications/{uid} doc flips to `verified`; the stream
      // below picks it up and shows the success state.
      // Adopt the Aadhaar name as the display name (the user can change
      // it later in Settings → Edit profile).
      final aadhaarName = result['name'];
      final uid = ref.read(currentUidProvider);
      if (aadhaarName is String &&
          aadhaarName.trim().isNotEmpty &&
          uid != null) {
        try {
          await ref
              .read(firestoreServiceProvider)
              .updateProfile(uid, name: aadhaarName.trim());
        } catch (_) {
          // Non-blocking: verification already succeeded; the name can
          // be set manually in Settings.
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = functionsErrorMessage(e,
            fallback: 'OTP verification failed. Please try again.',);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final kycStream =
        uid == null ? null : ref.watch(firestoreServiceProvider).watchKyc(uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify identity')),
      body: kycStream == null
          ? const Center(child: Text('Sign in to verify your identity.'))
          : StreamBuilder<KycVerification>(
              stream: kycStream,
              builder: (context, snap) {
                final kyc = snap.data;
                if (kyc != null && kyc.status == KycStatus.verified) {
                  return _VerifiedState(name: kyc.name);
                }
                return _buildForm(context);
              },
            ),
    );
  }

  /// iOS-style boxed OTP cell theme, tinted by state.
  PinTheme _pinTheme(Color border) {
    return PinTheme(
      width: 52,
      height: 60,
      textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(PhosphorIconsRegular.fingerprint,
            size: 64, color: AppColors.primary,),
        const SizedBox(height: 16),
        Text(
          'Verify your identity',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Verify your Aadhaar with an OTP. First, please read and accept '
          'the consent notice below — only then can you enter your Aadhaar '
          'number. Verification is required to sell items and to make '
          'offers, and verified sellers get a badge buyers trust. Your '
          'Aadhaar number is never stored.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_refId == null) ...[
          // Consent comes first: the Aadhaar field only appears after
          // the user has explicitly ticked the consent checkbox.
          _ConsentCard(
            consented: _consented,
            onChanged: (v) =>
                setState(() => _consented = v ?? false),
          ),
          if (_consented) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _aadhaarController,
              keyboardType: TextInputType.number,
              maxLength: 12,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Aadhaar number',
                hintText: 'XXXX XXXX XXXX',
              ),
            ),
          ],
        ],
        if (_refId != null) ...[
          const SizedBox(height: 16),
          Pinput(
            controller: _otpController,
            length: 6,
            enabled: !_busy,
            autofocus: true,
            showCursor: true,
            keyboardType: TextInputType.number,
            defaultPinTheme: _pinTheme(AppColors.divider),
            focusedPinTheme: _pinTheme(AppColors.primary),
            submittedPinTheme: _pinTheme(AppColors.primary),
            errorPinTheme: _pinTheme(AppColors.error),
            pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onCompleted: (_) => _verifyOtp(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else if (_refId == null && _consented)
          TregaButton(label: 'Send OTP', onPressed: _requestOtp)
        else if (_refId != null) ...[
          TregaButton(label: 'Verify OTP', onPressed: _verifyOtp),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _resendIn > 0 ? null : _resendOtp,
            child: Text(_resendLabel),
          ),
          TextButton(
            onPressed: () => setState(() {
              _refId = null;
              _otpController.clear();
              _stopCooldown();
            }),
            child: const Text('Use a different Aadhaar number'),
          ),
        ],
      ],
    );
  }
}

/// Consent gate shown before the Aadhaar number field.
///
/// The user must explicitly tick the checkbox before the Aadhaar entry
/// field (and the Send OTP button) is revealed. Ticking it is the
/// informed consent UIDAI expects for Aadhaar-based verification; the
/// timestamp is recorded server-side when the OTP is requested.
class _ConsentCard extends StatelessWidget {
  final bool consented;
  final ValueChanged<bool?> onChanged;

  const _ConsentCard({required this.consented, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.shieldCheck, size: 20),
              const SizedBox(width: 8),
              Text('Your consent',
                  style: theme.textTheme.titleMedium,),
            ],
          ),
          const SizedBox(height: 12),
          _bullet(theme,
              'Trega will use your Aadhaar number only to verify your identity, by sending an OTP to your Aadhaar-linked mobile number.',),
          _bullet(theme,
              'Your Aadhaar number is never stored — it is used once for this verification and discarded.',),
          _bullet(theme,
              'Verification is required to sell items and to make offers on Trega, and verified sellers get a trust badge.',),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => onChanged(!consented),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: consented, onChanged: onChanged),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'I have read and understood the above, and I give my consent for Trega to verify my identity using my Aadhaar number.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: theme.textTheme.bodyMedium),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _VerifiedState extends StatelessWidget {  final String? name;

  const _VerifiedState({this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SuccessCheck(size: 96),
            const SizedBox(height: 16),
            Text('Identity verified',
                style: Theme.of(context).textTheme.titleLarge,),
            if (name != null && name!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(name!, style: Theme.of(context).textTheme.bodyLarge),
            ],
            const SizedBox(height: 8),
            Text(
              'You now have the verified seller badge on your listings.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TregaButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
