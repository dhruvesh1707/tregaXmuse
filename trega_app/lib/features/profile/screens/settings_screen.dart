import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'help_screen.dart';
import 'saved_addresses_screen.dart';

/// App settings: notification preference, profile editing, about.
class SettingsScreen extends ConsumerWidget {
  static const String routeName = '/profile/settings';

  const SettingsScreen({super.key});

  Future<void> _editProfile(
      BuildContext context, WidgetRef ref, String uid,) async {
    final service = ref.read(firestoreServiceProvider);
    final user = await service.getUser(uid);
    if (!context.mounted) return;
    final nameController =
        TextEditingController(text: user?.name ?? '');
    final emailController =
        TextEditingController(text: user?.email ?? '');
    var saving = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13,),),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name =
                          nameController.text.trim();
                      final email =
                          emailController.text.trim();
                      if (name.length < 2) {
                        setDialogState(() =>
                            error = 'Enter your name.',);
                        return;
                      }
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        setDialogState(() =>
                            error =
                                'Enter a valid email.',);
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await service.updateProfile(uid,
                            name: name, email: email,);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Profile updated.',),),
                        );
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString().contains(
                                  'permission-denied',)
                              ? 'Save was blocked by the server. Update the app and try again.'
                              : 'Could not save. Try again.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    emailController.dispose();
  }

  /// Edits the seller's payout UPI ID. Owner-only — never shown to
  /// other users; used to release payouts after successful transactions.
  Future<void> _editPayoutUpi(
      BuildContext context, WidgetRef ref, String uid,) async {
    final service = ref.read(firestoreServiceProvider);
    final current = await service.getPayoutUpi(uid);
    if (!context.mounted) return;
    final upiController = TextEditingController(text: current ?? '');
    var saving = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Payout UPI ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We send your sale payouts here after a successful '
                'transaction. Only you and the Trega team can see this.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: upiController,
                keyboardType: TextInputType.text,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'UPI ID',
                  hintText: 'yourname@okhdfcbank',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13,),),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final upi = upiController.text.trim();
                      if (!_isValidUpi(upi)) {
                        setDialogState(() => error =
                            'Enter a valid UPI ID (e.g. name@okhdfcbank).',);
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await service.savePayoutUpi(uid, upi);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Payout UPI ID saved.',),),
                        );
                      } catch (_) {
                        setDialogState(() {
                          saving = false;
                          error = 'Could not save. Try again.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    upiController.dispose();
  }

  static bool _isValidUpi(String upi) =>
      RegExp(r'^[\w.\-]{2,64}@[a-zA-Z]{2,64}$').hasMatch(upi);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: uid == null
          ? const Center(child: Text('You are not signed in.'))
          : ListView(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8,),
                  child: Text(
                    'Notifications',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: AppColors.textSecondary,),
                  ),
                ),
                StreamBuilder<bool>(
                  stream:
                      service.watchNotificationSetting(uid),
                  builder: (context, snap) {
                    final enabled = snap.data ?? true;
                    return SwitchListTile(
                      title:
                          const Text('Push notifications'),
                      subtitle: const Text(
                          'Bids, offers, orders and listing updates',),
                      value: enabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) => service
                          .updateNotificationSetting(uid, v),
                    );
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8,),
                  child: Text(
                    'Account',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: AppColors.textSecondary,),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                      Icons.person_outline,
                      color: AppColors.primary,),
                  title: const Text('Edit profile'),
                  subtitle:
                      const Text('Name and email address'),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary,),
                  onTap: () =>
                      _editProfile(context, ref, uid),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8,),
                  child: Text(
                    'Selling',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: AppColors.textSecondary,),
                  ),
                ),
                StreamBuilder<String?>(
                  stream: service.watchPayoutUpi(uid),
                  builder: (context, snap) {
                    final upi = snap.data;
                    return ListTile(
                      leading: const Icon(Icons.payments_outlined,
                          color: AppColors.primary,),
                      title: const Text('Payout UPI ID'),
                      subtitle: Text(
                        upi ?? 'Not set — add it to receive payouts',),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary,),
                      onTap: () =>
                          _editPayoutUpi(context, ref, uid),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined,
                      color: AppColors.primary,),
                  title: const Text('Saved pickup addresses'),
                  subtitle:
                      const Text('Reuse them across listings'),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary,),
                  onTap: () => Navigator.of(context).pushNamed(
                      SavedAddressesScreen.routeName,),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.help_outline,
                      color: AppColors.primary,),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary,),
                  onTap: () => Navigator.of(context)
                      .pushNamed(HelpScreen.routeName),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8,),
                  child: Text(
                    'About',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: AppColors.textSecondary,),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline,
                      color: AppColors.primary,),
                  title: Text('Trega'),
                  subtitle: Text(
                      'Version 1.0.0 • India’s marketplace for pre-owned gear',),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Made with care for India’s pre-owned gear community.',
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
