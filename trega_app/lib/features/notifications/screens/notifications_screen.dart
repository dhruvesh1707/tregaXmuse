import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';

/// Push + in-app notification inbox.
///
/// Notification types: bid updates, offer accepted/rejected, order status,
/// listing review decisions, price drops on wishlist items.
///
/// Push arrives via FCM (`firebase_messaging`; token registered to the user
/// doc). In-app inbox persistence is a future step — for now the screen
/// shows a placeholder until the `notifications/{uid}/items` collection
/// exists. Delete the placeholder once real data flows.
class NotificationsScreen extends StatelessWidget {
  static const String routeName = '/notifications';

  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: replace with paginated GET /notifications.
    const items = [
      _TregaNotification(
        icon: Icons.gavel,
        title: 'Your bid was accepted',
        body: 'MacBook Pro 14" M3 Pro — proceed to payment within 24h.',
        time: '2h ago',
        unread: true,
      ),
      _TregaNotification(
        icon: Icons.local_shipping_outlined,
        title: 'Order picked up',
        body: 'iPhone 13 is on its way from Mumbai.',
        time: '5h ago',
        unread: true,
      ),
      _TregaNotification(
        icon: Icons.verified_outlined,
        title: 'Listing approved',
        body: 'Your Sony A7 III listing is now live.',
        time: '1d ago',
        unread: false,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () {
              // TODO: mark all as read.
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'All caught up',
              subtitle: 'We’ll notify you about bids, offers and orders.',
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                return ListTile(
                  tileColor: n.unread
                      ? AppColors.primarySoft.withOpacity(0.5)
                      : null,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(n.icon, color: AppColors.primary),
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight:
                          n.unread ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text('${n.body}\n${n.time}'),
                  isThreeLine: true,
                  onTap: () {
                    // TODO: mark read + deep-link to relevant screen.
                  },
                );
              },
            ),
    );
  }
}

class _TregaNotification {
  final IconData icon;
  final String title;
  final String body;
  final String time;
  final bool unread;

  const _TregaNotification({
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
  });
}
