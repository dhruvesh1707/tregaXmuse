import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/trega_toast.dart';

/// Help centre: how Trega works + how to reach support.
///
/// Support inbox — matches the Contact page (support@trega.in).
class HelpScreen extends StatelessWidget {
  static const String routeName = '/profile/help';

  static const _supportEmail = 'support@trega.in';

  const HelpScreen({super.key});

  Future<void> _emailSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: const {'subject': 'Trega support'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      await showTregaToast(
        context,
        'Write to $_supportEmail — we reply within a day.',
        title: 'Contact support',
        kind: TregaToastKind.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.headset,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How can we help?',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Answers to the most common questions about buying and selling on Trega.',
                        style: textTheme.bodySmall?.copyWith(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _SectionLabel('Selling'),
          const _FaqTile(
            index: 0,
            question: 'How does selling work?',
            answer:
                'Tap Sell, capture your item with the camera, add details and a price, and publish — '
                'your listing goes live immediately. Once it sells, we collect the item from the '
                'pickup address you provided.',
          ),
          const _FaqTile(
            index: 1,
            question: 'Is my address visible to buyers?',
            answer:
                'Never. Your pickup address is visible only to you and the Trega team, and is used solely '
                'to collect sold items. Buyers only see the city/area on the listing.',
          ),
          const _FaqTile(
            index: 2,
            question: 'When do I get paid as a seller?',
            answer:
                'After we pick up your item and verify it matches the listing, the payout is released '
                'to your registered bank account / UPI. You’ll get a notification at every step.',
          ),
          const _SectionLabel('Bids & offers'),
          const _FaqTile(
            index: 3,
            question: 'How do bids & offers work?',
            answer:
                'Every listing has bidding switched on — there are no chats on Trega. '
                'Tap “Place bid” on a listing, enter your offer, and the seller can accept or decline. '
                'If your bid is accepted, you’ll be guided to payment within 24 hours.',
          ),
          const _SectionLabel('Trust & safety'),
          const _FaqTile(
            index: 4,
            question: 'Why was my listing flagged or removed?',
            answer:
                'Listings get flagged for misleading or blurry photos, prohibited items, a price far from '
                'market value, or missing details. Fix the issue and publish again — or write to us below.',
          ),
          const _FaqTile(
            index: 5,
            question: 'Is my Aadhaar data safe?',
            answer:
                'Aadhaar verification is optional and only used to earn the “Verified seller” badge. '
                'OTP verification happens directly with our verification partner; Trega never stores '
                'your Aadhaar number.',
          ),
          const SizedBox(height: 8),
          // ── Contact card ────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(PhosphorIconsRegular.envelope,
                    color: Colors.white, size: 24,),
              ),
              title: Text(
                'Still need help?',
                style: textTheme.titleSmall,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Write to us — we reply within a day.',
                  style: textTheme.bodySmall,
                ),
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Email us',
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              onTap: () => _emailSupport(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  final int index;

  const _FaqTile(
      {required this.question, required this.answer, this.index = 0,});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Entrance(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        // ExpansionTile draws hairline dividers above/below its children —
        // hide them so they don't double up with the container border.
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 16),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.textSecondary,
            title: Text(question, style: textTheme.titleSmall),
            children: [
              Text(
                answer,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    }
  }
