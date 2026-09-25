import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'legal_content.dart';

/// Arguments for [LegalPageScreen.routeName].
class LegalPageArgs {
  final String pageId;

  const LegalPageArgs(this.pageId);
}

/// Reader for the legal pages (Privacy Policy, Terms, …) listed under the
/// "Legal" section of the profile page.
class LegalPageScreen extends StatelessWidget {
  static const String routeName = '/profile/legal';

  final String pageId;

  const LegalPageScreen({super.key, required this.pageId});

  @override
  Widget build(BuildContext context) {
    final page = legalPages[pageId];
    if (page == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Page not found.')),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(page.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Last updated: ${page.updated}',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final section in page.sections) ...[
            Text(
              section.heading,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              section.body,
              style: textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
