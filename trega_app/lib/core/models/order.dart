import 'firestore_convert.dart';
import 'listing.dart';
import 'product.dart';
import 'user.dart';

/// Order lifecycle, matching the Cloud Functions data model.
///
/// Firestore `status` values: `placed` → `pickup_scheduled` → `picked_up` →
/// `in_transit` → `delivered`, plus `cancelled` and `returned`. Payment state
/// is tracked separately in `paymentStatus` (`PENDING`|`SUCCESS`|`FAILED`|
/// `USER_DROPPED`).
enum OrderStatus {
  paymentPending,
  confirmed,
  pickupScheduled,
  pickedUp,
  inTransit,
  outForDelivery,
  delivered,
  cancelled,
  refunded,
}

extension OrderStatusLabel on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.paymentPending:
        return 'Payment pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.pickupScheduled:
        return 'Pickup scheduled';
      case OrderStatus.pickedUp:
        return 'Picked up';
      case OrderStatus.inTransit:
        return 'In transit';
      case OrderStatus.outForDelivery:
        return 'Out for delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.refunded:
        return 'Refunded';
    }
  }

  bool get isTerminal {
    return this == OrderStatus.delivered ||
        this == OrderStatus.cancelled ||
        this == OrderStatus.refunded;
  }

  /// Maps a Firestore wire value to the closest in-memory status.
  static OrderStatus fromWire(String value) {
    switch (value) {
      case 'placed':
        return OrderStatus.confirmed;
      case 'pickup_scheduled':
        return OrderStatus.pickupScheduled;
      case 'picked_up':
        return OrderStatus.pickedUp;
      case 'in_transit':
        return OrderStatus.inTransit;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'returned':
        return OrderStatus.refunded;
      default:
        return OrderStatus.paymentPending;
    }
  }

  static OrderStatus fromJson(String value) {
    return OrderStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => OrderStatus.paymentPending,
    );
  }
}

class Order {
  final String id;
  final Listing listing;
  final AppUser buyer;
  final double amount;
  final OrderStatus status;
  final String? trackingId;
  final String? pickupAddress;
  final String? deliveryAddress;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Order({
    required this.id,
    required this.listing,
    required this.buyer,
    required this.amount,
    this.status = OrderStatus.paymentPending,
    this.trackingId,
    this.pickupAddress,
    this.deliveryAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      listing: Listing.fromJson(json['listing'] as Map<String, dynamic>),
      buyer: AppUser.fromJson(json['buyer'] as Map<String, dynamic>),
      amount: (json['amount'] as num).toDouble(),
      status: OrderStatusLabel.fromJson(json['status'] as String? ?? ''),
      trackingId: json['tracking_id'] as String?,
      pickupAddress: json['pickup_address'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'listing': listing.toJson(),
      'buyer': buyer.toJson(),
      'amount': amount,
      'status': status.name,
      'tracking_id': trackingId,
      'pickup_address': pickupAddress,
      'delivery_address': deliveryAddress,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Firestore deserialization for `orders/{orderId}` documents.
///
/// Canonical fields: `listingId`, `bidId?`, `buyerId`, `sellerId`, `amount`,
/// `currency`, `paymentStatus`, `status`, `cfOrderId?`, `trackingNote?`,
/// `paidAt?`, `createdAt`.
///
/// Orders are created server-side by the `createCashfreeOrder` callable —
/// clients never write order docs directly. The order doc carries no listing
/// snapshot, so the nested [Listing] is a minimal placeholder (id only);
/// UI resolves the title/photo via the listing doc when needed.
extension OrderFirestore on Order {
  static Order fromFirestore(Map<String, dynamic> data, String docId) {
    final listingId = data['listingId'] as String? ?? '';
    return Order(
      id: docId,
      listing: Listing(
        id: listingId,
        product: Product.empty,
        seller: AppUser(
          id: data['sellerId'] as String? ?? '',
          name: '',
          phone: '',
        ),
        price: (data['amount'] as num? ?? 0).toDouble(),
        createdAt: firestoreDate(data['createdAt']),
      ),
      buyer: AppUser(
        id: data['buyerId'] as String? ?? '',
        name: '',
        phone: '',
      ),
      amount: (data['amount'] as num? ?? 0).toDouble(),
      status: OrderStatusLabel.fromWire(data['status'] as String? ?? ''),
      trackingId: data['trackingNote'] as String?,
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['createdAt']),
    );
  }
}
