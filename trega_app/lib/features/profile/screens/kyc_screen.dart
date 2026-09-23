import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/kyc_verification.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/trega_button.dart';

/// Aadhaar KYC with OTP (BulkPe).
///
/// Flow: enter 12-digit Aadhaar → [requestAadhaarOtp] sends an OTP to the
/// Aadhaar-linked mobile → enter OTP → [verifyAadhaarOtp] completes
/// verification. The Aadhaar number is never stored anywhere — it travels
/// only to our Cloud Function over TLS.
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
  String? _error;

  @override
  void dispose() {
    _aadhaarController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP sent to your Aadhaar-linked mobile number.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send the OTP. Please try again.';
      });
    }
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
      await ref
          .read(functionsServiceProvider)
          .verifyAadhaarOtp(_refId!, otp);
      if (!mounted) return;
      setState(() => _busy = false);
      // The kycVerifications/{uid} doc flips to `verified`; the stream
      // below picks it up and shows the success state.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'OTP verification failed. Please try again.';
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

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.fingerprint,
            size: 64, color: AppColors.primary),
        const SizedBox(height: 16),
        Text(
          'Become a verified seller',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Verify your Aadhaar with an OTP. Verified sellers get a badge '
          'and buyers trust them more. Your Aadhaar number is never stored.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _aadhaarController,
          keyboardType: TextInputType.number,
          maxLength: 12,
          enabled: _refId == null && !_busy,
          decoration: const InputDecoration(
            labelText: 'Aadhaar number',
            hintText: 'XXXX XXXX XXXX',
          ),
        ),
        if (_refId != null) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            enabled: !_busy,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'OTP',
              hintText: 'Enter the 6-digit OTP',
            ),
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
        else if (_refId == null)
          TregaButton(label: 'Send OTP', onPressed: _requestOtp)
        else ...[
          TregaButton(label: 'Verify OTP', onPressed: _verifyOtp),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              _refId = null;
              _otpController.clear();
            }),
            child: const Text('Use a different Aadhaar number'),
          ),
        ],
      ],
    );
  }
}

class _VerifiedState extends StatelessWidget {
  final String? name;

  const _VerifiedState({this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified,
                size: 80, color: AppColors.success),
            const SizedBox(height: 16),
            Text('Identity verified',
                style: Theme.of(context).textTheme.titleLarge),
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
