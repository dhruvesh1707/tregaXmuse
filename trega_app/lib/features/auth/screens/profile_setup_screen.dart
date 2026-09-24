import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/trega_button.dart';
import '../../home/screens/home_screen.dart';
import 'phone_auth_screen.dart';

/// First-run profile setup, shown right after OTP sign-in when the user is
/// new (or never completed setup). Collects the display name and email used
/// across the marketplace (order updates, seller contact via support).
class ProfileSetupScreen extends ConsumerStatefulWidget {
  static const String routeName = '/auth/setup';

  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _saving = false;
  String? _error;

  static final _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Please tell us your name.');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacementNamed(PhoneAuthScreen.routeName);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateProfile(uid, name: name, email: email);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(HomeScreen.routeName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlySaveError(e);
      });
    }
  }

  /// Surfaces the real failure reason instead of a generic message, so a
  /// blocked save (e.g. stale Firestore rules on the backend) is
  /// diagnosable instead of mysterious.
  String _friendlySaveError(Object e) {
    final msg = e.toString();
    if (msg.contains('permission-denied')) {
      return 'Save was blocked by the server (permission-denied). '
          'Please pull the latest app update and try again.';
    }
    if (msg.contains('unavailable') || msg.contains('network')) {
      return 'No connection. Check your internet and try again.';
    }
    return 'Could not save your profile. Please try again. ($msg)';
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
                'Set up your profile',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Buyers and sellers will see your name. We use your email '
                'for order and bid updates.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  hintText: 'e.g. Aarav Sharma',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
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
              if (_saving)
                const Center(child: CircularProgressIndicator())
              else
                TregaButton(
                  label: 'Continue',
                  onPressed: _save,
                ),
              const Spacer(),
              Text(
                'You can update these later from Profile → Settings.',
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
