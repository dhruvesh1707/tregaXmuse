import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_state.dart';

/// Push + in-app notification inbox.
///
/// Reads the user's inbox at `users/{uid}/notifications` (written
/// server-side by Cloud Functions on bid / order / listing events).
/// Tapping a notification marks it read; "Mark all read" flips every
/// unread item via a batched write.
class NotificationsScreen extends ConsumerStatefulWidget {
  static const String routeName = '/notifications';

  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends ConsumerState<NotificationsScreen> {
  /// Bumped to force the inbox stream to re-subscribe (retry / refresh).
  int _streamVersion = 0;

  void _refresh() => setState(() => _streamVersion++);

  IconData _iconForType(String type) {
    switch (type) {
      case 'bid_received':
        return Icons.gavel;
      case 'outbid':
        return Icons.trending_up;
      case 'bid_accepted':
        return Icons.check_circle_outline;
      case 'bid_rejected':
        return Icons.cancel_outlined;
      case 'listing_flagged':
        return Icons.flag_outlined;
      case 'bid':
        return Icons.gavel;
      case 'order':
        return Icons.local_shipping_outlined;
      case 'listing':
        return Icons.verified_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Future<void> _markAllRead() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .markAllNotificationsRead(uid);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update notifications.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: uid == null ? null : _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: uid == null
          ? const EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'Not signed in',
              subtitle: 'Sign in to see your notifications.',
            )
          : StreamBuilder<List<AppNotification>>(
              key: ValueKey(_streamVersion),
              stream: service.watchNotifications(uid),
              builder: (context, snap) {
                if (snap.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(),);
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon:
                        Icons.notifications_off_outlined,
                    title: 'Couldn’t load notifications',
                    subtitle:
                        'Check your connection and pull to try again.',
                    actionLabel: 'Retry',
                    onAction: _refresh,
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return const EmptyState(
                    icon:
                        Icons.notifications_none_outlined,
                    title: 'All caught up',
                    subtitle:
                        'We’ll notify you about bids, offers and orders.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      final time = n.createdAt == null
                          ? ''
                          : timeAgo(n.createdAt!);
                      return ListTile(
                        tileColor: n.read
                            ? null
                            : AppColors.primarySoft
                                .withValues(alpha: 0.5),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Icon(
                              _iconForType(n.type),
                              color: AppColors.primary,),
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight: n.read
                                ? FontWeight.w400
                                : FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                            '${n.body}${time.isEmpty ? '' : '\n$time'}',),
                        isThreeLine: true,
                        onTap: n.read
                            ? null
                            : () => service
                                .markNotificationRead(uid, n.id)
                                .catchError((_) {}),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
