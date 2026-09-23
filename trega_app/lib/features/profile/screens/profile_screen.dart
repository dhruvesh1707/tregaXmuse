import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/kyc_verification.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/screens/phone_auth_screen.dart';
import '../../bids/screens/bids_offers_screen.dart';
import '../../orders/screens/orders_screen.dart';
import '../../wishlist/screens/wishlist_screen.dart';
import 'help_screen.dart';
import 'kyc_screen.dart';
import 'my_listings_screen.dart';
import 'settings_screen.dart';

/// Account hub: profile, verification status, listings, orders, settings.
///
/// Streams `users/{uid}` and `kycVerifications/{uid}` from Firestore.
class ProfileScreen extends ConsumerWidget {
  static const String routeName = '/profile';

  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authServiceProvider).signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        PhoneAuthScreen.routeName,
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: uid == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'You are not signed in.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pushNamed(PhoneAuthScreen.routeName),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ),
            )
          : StreamBuilder<AppUser?>(
              stream: service.watchUser(uid),
              builder: (context, userSnap) {
                final user = userSnap.data;
                return StreamBuilder<KycVerification>(
                  stream: service.watchKyc(uid),
                  builder: (context, kycSnap) {
                    final kyc = kycSnap.data;
                    final verified =
                        kyc?.status == KycStatus.verified ||
                            (user?.isVerifiedSeller ?? false);
                    return ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 32,
                                    backgroundColor: AppColors.primarySoft,
                                    child: Icon(Icons.person,
                                        size: 36,
                                        color: AppColors.primary,),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                (user?.name.isNotEmpty ??
                                                        false)
                                                    ? user!.name
                                                    : 'Trega user',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge,
                                              ),
                                            ),
                                            if (verified)
                                              const Icon(Icons.verified,
                                                  size: 20,
                                                  color:
                                                      AppColors.primary,),
                                          ],
                                        ),
                                        Text(
                                          user?.phone ?? '',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  color: AppColors
                                                      .textSecondary,),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.star,
                                                size: 16,
                                                color: AppColors.accent,),
                                            Text(
                                              ' ${user?.rating ?? '–'} '
                                              '(${user?.reviewsCount ?? 0} reviews)',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!verified)
                          _MenuTile(
                            icon: Icons.verified_outlined,
                            title: 'Become a verified seller',
                            subtitle: 'Verify your Aadhaar with OTP',
                            onTap: () => Navigator.of(context)
                                .pushNamed(KycScreen.routeName),
                          ),
                        _MenuTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'My Listings',
                          subtitle: 'Manage what you’re selling',
                          onTap: () => Navigator.of(context)
                              .pushNamed(
                                  MyListingsScreen.routeName,),
                        ),
                        _MenuTile(
                          icon: Icons.gavel_outlined,
                          title: 'Bids & Offers',
                          subtitle: 'Track negotiations',
                          onTap: () => Navigator.of(context)
                              .pushNamed(BidsOffersScreen.routeName),
                        ),
                        _MenuTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'My Orders',
                          subtitle: 'Purchases & deliveries',
                          onTap: () => Navigator.of(context)
                              .pushNamed(OrdersScreen.routeName),
                        ),
                        _MenuTile(
                          icon: Icons.favorite_outline,
                          title: 'Wishlist',
                          subtitle: 'Saved items',
                          onTap: () => Navigator.of(context)
                              .pushNamed(WishlistScreen.routeName),
                        ),
                        _MenuTile(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          onTap: () => Navigator.of(context)
                              .pushNamed(
                                  SettingsScreen.routeName,),
                        ),
                        _MenuTile(
                          icon: Icons.help_outline,
                          title: 'Help & Support',
                          onTap: () => Navigator.of(context)
                              .pushNamed(HelpScreen.routeName),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton.icon(
                            onPressed: () => _logout(context, ref),
                            icon: const Icon(Icons.logout,
                                color: AppColors.error,),
                            label: const Text('Log out',
                                style:
                                    TextStyle(color: AppColors.error),),
                            style: OutlinedButton.styleFrom(
                              side:
                                  const BorderSide(color: AppColors.error),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary,),
      onTap: onTap,
    );
  }
}
