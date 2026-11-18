import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/update/force_update.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_scaffold.dart';
import 'splash_screen.dart';

/// Blocking update screen for the force-update gate.
///
/// Non-dismissible on purpose: no back button, no skip, no close, and
/// [PopScope] blocks the Android system back gesture. It is reached via
/// pushReplacementNamed from the splash gate, so there is nothing to
/// pop back to.
///
/// Android offers the Play Store link. iOS never shows a store link:
/// iPhone builds are sideloaded and there is no App Store entry, so the
/// copy only asks for the latest build. Re-check re-runs the gate and
/// re-enters normal routing through the splash screen when the install
/// is no longer below the minimum.
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  static const String routeName = '/update-required';

  const UpdateRequiredScreen({super.key});

  @override
  ConsumerState<UpdateRequiredScreen> createState() =>
      _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState
    extends ConsumerState<UpdateRequiredScreen> {
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.trega.trega';

  bool _checking = false;

  Future<void> _openStore() async {
    final uri = Uri.parse(_playStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    // If the store cannot be opened, stay on this screen.
  }

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    final blocked =
        await isForceUpdateRequired(ref.read(firestoreServiceProvider));
    if (!mounted) return;
    if (!blocked) {
      Navigator.of(context)
          .pushReplacementNamed(SplashScreen.routeName);
      return;
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return PopScope(
      canPop: false,
      child: TregaScaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/logo/trega_logo.png',
                  width: 180,
                ),
                const SizedBox(height: 32),
                Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  isAndroid
                      ? 'A newer version of Trega is required to keep using the app. Update to the latest version to continue.'
                      : 'A new build of Trega is required to keep using the app. Install the latest build to continue.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 32),
                if (isAndroid) ...[
                  TregaButton(
                    label: 'Update Trega',
                    onPressed: _openStore,
                  ),
                  const SizedBox(height: 12),
                  TregaButton(
                    label: 'Re-check',
                    secondary: true,
                    onPressed: _checking ? null : _recheck,
                  ),
                ] else ...[
                  TregaButton(
                    label: 'Re-check',
                    onPressed: _checking ? null : _recheck,
                  ),
                ],
                if (_checking) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Checking for the latest version.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
