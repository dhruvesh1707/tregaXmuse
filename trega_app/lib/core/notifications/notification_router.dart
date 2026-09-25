import 'package:flutter/material.dart';

import '../../features/bids/screens/bids_offers_screen.dart';
import '../../features/checkout/screens/checkout_screen.dart';
import '../../features/listing_detail/screens/listing_detail_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/orders/screens/orders_screen.dart';
import '../../features/profile/screens/kyc_screen.dart';
import '../../features/profile/screens/my_listings_screen.dart';
import '../models/app_notification.dart';

/// Where a notification tap should land: a named route plus its arguments.
class NotificationTarget {
  final String routeName;
  final Object? arguments;

  const NotificationTarget(this.routeName, [this.arguments]);
}

/// A notification tap that arrives while the app is terminated. It can't be
/// routed until the navigator exists, so it is stashed here and consumed by
/// the splash screen once initial routing settles.
NotificationTarget? pendingNotificationTarget;

/// Resolves a notification (inbox doc or FCM data payload) to the screen it
/// is about. Returns null when there is no sensible destination — the tap
/// then just marks the notification read.
///
/// Mapping:
/// - bid_received  -> Offers Received tab (seller reviews the bid)
/// - outbid        -> listing detail (buyer raises their bid)
/// - bid_accepted  -> checkout (winner pays)
/// - bid_rejected  -> My Offers tab
/// - listing_flagged -> My Listings (the listing itself is down)
/// - kyc_verified / kyc_rejected -> KYC screen
/// - order         -> order tracking (or Orders when no order id)
NotificationTarget? targetForNotification({
  required String type,
  required Map<String, dynamic> data,
}) {
  String? str(String key) {
    final v = data[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  final listingId = str('listingId');
  final bidId = str('bidId');
  final orderId = str('orderId');

  switch (type) {
    case 'bid_received':
      return const NotificationTarget(
        BidsOffersScreen.routeName,
        BidsOffersArgs(initialTab: 1),
      );
    case 'outbid':
      if (listingId != null) {
        return NotificationTarget(
          ListingDetailScreen.routeName,
          ListingDetailArgs(listingId: listingId),
        );
      }
      return const NotificationTarget(BidsOffersScreen.routeName);
    case 'bid_accepted':
      if (bidId != null) {
        return NotificationTarget(
          CheckoutScreen.routeName,
          CheckoutArgs(bidId: bidId),
        );
      }
      return const NotificationTarget(BidsOffersScreen.routeName);
    case 'bid_rejected':
      return const NotificationTarget(
        BidsOffersScreen.routeName,
        BidsOffersArgs(initialTab: 0),
      );
    case 'listing_flagged':
      return const NotificationTarget(MyListingsScreen.routeName);
    case 'kyc_verified':
    case 'kyc_rejected':
      return const NotificationTarget(KycScreen.routeName);
    case 'order':
      if (orderId != null) {
        return NotificationTarget(OrderTrackingScreen.routeName, orderId);
      }
      return const NotificationTarget(OrdersScreen.routeName);
    case 'bid':
      return const NotificationTarget(BidsOffersScreen.routeName);
    case 'listing':
      return const NotificationTarget(MyListingsScreen.routeName);
    default:
      return null;
  }
}

/// Resolves an [AppNotification] to its tap target.
NotificationTarget? targetForAppNotification(AppNotification n) =>
    targetForNotification(type: n.type, data: n.data);

/// Pushes [target] onto the navigator.
void openNotificationTarget(BuildContext context, NotificationTarget target) {
  Navigator.of(context)
      .pushNamed(target.routeName, arguments: target.arguments);
}
