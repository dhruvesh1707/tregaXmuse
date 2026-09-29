import 'package:flutter/material.dart';

import '../icons/phosphor_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_shadows.dart';
import 'motion.dart';
import 'trega_button.dart';

/// Full failure state: what went wrong, plus a retry action.
///
/// Sibling of [EmptyState] — same visual language (fade-slide entrance,
/// icon medallion, title, subtitle) but with a primary retry button.
/// Use it in every `error:` / `hasError` branch so a failed load never
/// strands the user on a spinner or a dead screen.
class TregaErrorState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRetry;
  final String retryLabel;
  final IconData icon;

  const TregaErrorState({
    super.key,
    this.title = "Couldn't load this",
    this.subtitle = 'Check your connection and try again.',
    required this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = PhosphorIconsRegular.cloudSlash,
  });

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  gradient: AppGradients.heroBrown,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.button,
                ),
                child: Icon(icon, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              TregaButton(
                label: retryLabel,
                onPressed: onRetry,
                expanded: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
