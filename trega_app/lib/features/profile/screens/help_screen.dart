import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// Help centre: how Trega works + how to reach support.
///
/// (Support email is a placeholder — swap `care@trega.in` for the real
/// support inbox before launch.)
class HelpScreen extends StatelessWidget {
  static const String routeName = '/profile/help';

  static const _supportEmail = 'care@trega.in';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email us at $_supportEmail')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _FaqTile(
            question: 'How do bids & offers work?',
            answer:
                'Every listing has bidding switched on — there are no chats on Trega. '
                'Tap “Place bid” on a listing, enter your offer, and the seller can accept or decline. '
                'If your bid is accepted, you’ll be guided to payment within 24 hours.',
          ),
          const _FaqTile(
            question: 'How does selling work?',
            answer:
                'Tap Sell, capture your item with the camera, add details and a price, and publish. '
                'Our team reviews every listing for accuracy before it goes live — usually within a few hours. '
                'Once it sells, we collect the item from the pickup address you provided.',
          ),
          const _FaqTile(
            question: 'Is my address visible to buyers?',
            answer:
                'Never. Your pickup address is visible only to you and the Trega team, and is used solely '
                'to collect sold items. Buyers only see the city/area on the listing.',
          ),
          const _FaqTile(
            question: 'When do I get paid as a seller?',
            answer:
                'After we pick up your item and verify it matches the listing, the payout is released '
                'to your registered bank account / UPI. You’ll get a notification at every step.',
          ),
          const _FaqTile(
            question: 'Why was my listing rejected?',
            answer:
                'Listings are reviewed for accuracy and safety. Common reasons: blurry or misleading photos, '
                'a price far from market value, a prohibited item, or missing details. '
                'Fix the issue and publish again — or write to us below.',
          ),
          const _FaqTile(
            question: 'Is my Aadhaar data safe?',
            answer:
                'Aadhaar verification is optional and only used to earn the “Verified seller” badge. '
                'OTP verification happens directly with our verification partner; Trega never stores '
                'your Aadhaar number.',
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mail_outline,
                    color: AppColors.primary),
              ),
              title: const Text('Still need help?'),
              subtitle: Text('Email us at $_supportEmail'),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
              onTap: () => _emailSupport(context),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(
          question,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        iconColor: AppColors.primary,
        childrenPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            answer,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
