import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/kyc_verification.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/trega_toast.dart';
import '../../auth/screens/phone_auth_screen.dart';
import '../../bids/screens/bids_offers_screen.dart';
import '../../orders/screens/orders_screen.dart';
import '../../wishlist/screens/wishlist_screen.dart';
import 'help_screen.dart';
import 'legal/legal_page_screen.dart';
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
                // While the profile loads, shimmer the real header layout
                // instead of a spinner — data just fades in when ready.
                final profileLoading =
                    userSnap.connectionState ==
                            ConnectionState.waiting &&
                        user == null;
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
                          child: Skeletonizer(
                            enabled: profileLoading,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    _AvatarEditor(
                                      uid: uid,
                                      avatarUrl: user?.avatarUrl,
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
                                                const Icon(PhosphorIconsRegular.sealCheck,
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
                                              const Icon(PhosphorIconsRegular.star,
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
                        ),
                        if (!verified)
                          _MenuTile(
                            index: 0,
                            icon: PhosphorIconsRegular.sealCheck,
                            title: 'Become a verified seller',
                            subtitle: 'Verify your Aadhaar with OTP',
                            onTap: () => Navigator.of(context)
                                .pushNamed(KycScreen.routeName),
                          ),
                        _MenuTile(
                            index: 1,
                          icon: PhosphorIconsRegular.package,
                          title: 'My Listings',
                          subtitle: 'Manage what you’re selling',
                          onTap: () => Navigator.of(context)
                              .pushNamed(
                                  MyListingsScreen.routeName,),
                        ),
                        _MenuTile(
                            index: 2,
                          icon: PhosphorIconsRegular.gavel,
                          title: 'Bids & Offers',
                          subtitle: 'Track negotiations',
                          onTap: () => Navigator.of(context)
                              .pushNamed(BidsOffersScreen.routeName),
                        ),
                        _MenuTile(
                            index: 3,
                          icon: PhosphorIconsRegular.package,
                          title: 'My Orders',
                          subtitle: 'Purchases & deliveries',
                          onTap: () => Navigator.of(context)
                              .pushNamed(OrdersScreen.routeName),
                        ),
                        _MenuTile(
                            index: 4,
                          icon: PhosphorIconsRegular.heart,
                          title: 'Wishlist',
                          subtitle: 'Saved items',
                          onTap: () => Navigator.of(context)
                              .pushNamed(WishlistScreen.routeName),
                        ),
                        _MenuTile(
                            index: 5,
                          icon: PhosphorIconsRegular.gear,
                          title: 'Settings',
                          onTap: () => Navigator.of(context)
                              .pushNamed(
                                  SettingsScreen.routeName,),
                        ),
                        _MenuTile(
                            index: 6,
                          icon: PhosphorIconsRegular.question,
                          title: 'Help & Support',
                          onTap: () => Navigator.of(context)
                              .pushNamed(HelpScreen.routeName),
                        ),
                        const Padding(
                          padding:
                              EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Legal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        _MenuTile(
                            index: 7,
                          icon: PhosphorIconsRegular.shieldCheck,
                          title: 'Privacy Policy',
                          onTap: () => Navigator.of(context).pushNamed(
                            LegalPageScreen.routeName,
                            arguments:
                                const LegalPageArgs('privacy'),
                          ),
                        ),
                        _MenuTile(
                            index: 8,
                          icon: PhosphorIconsRegular.handshake,
                          title: 'Terms of Service',
                          onTap: () => Navigator.of(context).pushNamed(
                            LegalPageScreen.routeName,
                            arguments:
                                const LegalPageArgs('terms'),
                          ),
                        ),
                        _MenuTile(
                            index: 9,
                          icon: PhosphorIconsRegular.wallet,
                          title: 'Refund & Cancellation',
                          onTap: () => Navigator.of(context).pushNamed(
                            LegalPageScreen.routeName,
                            arguments:
                                const LegalPageArgs('refund'),
                          ),
                        ),
                        _MenuTile(
                            index: 10,
                          icon: PhosphorIconsRegular.info,
                          title: 'About Trega',
                          onTap: () => Navigator.of(context).pushNamed(
                            LegalPageScreen.routeName,
                            arguments:
                                const LegalPageArgs('about'),
                          ),
                        ),
                        _MenuTile(
                            index: 11,
                          icon: PhosphorIconsRegular.envelope,
                          title: 'Contact Us',
                          onTap: () => Navigator.of(context).pushNamed(
                            LegalPageScreen.routeName,
                            arguments:
                                const LegalPageArgs('contact'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton.icon(
                            onPressed: () => _logout(context, ref),
                            icon: const Icon(PhosphorIconsRegular.signOut,
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
  final int index;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Entrance(
      index: index,
      child: ListTile(
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
      trailing: const Icon(PhosphorIconsRegular.caretRight,
          color: AppColors.textSecondary,),
      onTap: onTap,
      ),
    );
  }
}


/// Profile photo editor: tap the camera badge to take a photo or choose
/// one from the gallery (the ONLY place gallery upload is allowed — the
/// sell flow stays camera-only), crop it square, upload to Firebase
/// Storage, and save the URL on the user doc. Cloud-stored, so the photo
/// survives reinstalls.
class _AvatarEditor extends ConsumerStatefulWidget {
  final String uid;
  final String? avatarUrl;

  const _AvatarEditor({required this.uid, this.avatarUrl});

  @override
  ConsumerState<_AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends ConsumerState<_AvatarEditor> {
  bool _uploading = false;

  Future<void> _changeAvatar() async {
    // Profile picture is the one place gallery upload is allowed.
    final source = await showCupertinoModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.images),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    // Square crop so the round avatar never shows a stretched photo.
    final cropped = await ImageCropper().cropImage(
      sourcePath: image.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop profile photo',
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop profile photo',
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(storageServiceProvider)
          .uploadAvatar(widget.uid, XFile(cropped.path));
      await ref
          .read(firestoreServiceProvider)
          .updateProfile(widget.uid, avatarUrl: url);
      if (!mounted) return;
      await showTregaToast(
        context,
        'Your new photo is live on your profile.',
        title: 'Photo updated',
        kind: TregaToastKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      await showTregaToast(
        context,
        'Could not update your photo. Please try again.',
        title: 'Something went wrong',
        kind: TregaToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = widget.avatarUrl?.isNotEmpty ?? false;
    const fallbackIcon = Icon(
      PhosphorIconsRegular.user,
      size: 36,
      color: AppColors.primary,
    );
    // A dead avatar URL (deleted object, revoked token, blocked read)
    // must fall back to the default icon — CircleAvatar's backgroundImage
    // has no error slot and renders a broken tile instead.
    return Stack(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: ClipOval(
            child: hasAvatar
                ? CachedNetworkImage(
                    imageUrl: widget.avatarUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppColors.primarySoft,
                      child: fallbackIcon,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.primarySoft,
                      child: fallbackIcon,
                    ),
                  )
                : Container(
                    color: AppColors.primarySoft,
                    child: fallbackIcon,
                  ),
          ),
        ),
        if (_uploading)
          const Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _changeAvatar,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  PhosphorIconsRegular.camera,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
