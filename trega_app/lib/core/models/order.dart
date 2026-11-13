import 'firestore_convert.dart';
import 'listing.dart';
import 'product.dart';
import 'user.dart';

/// Order lifecycle, matching the Cloud Functions data model.
///
/// Firestore `status` values: `placed` → `pickup_scheduled` → `picked_up` →
/// `in_transit` → `out_for_delivery` → `delivered`, plus `cancelled` and
/// `returned`. Payment state is tracked separately in `paymentStatus`
/// (`PENDING`|`SUCCESS`|`FAILED`|`USER_DROPPED`).
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
      case 'out_for_delivery':
        return OrderStatus.outForDelivery;
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
  /// Purchase-time snapshot of the listing's title and first photo,
  /// written server-side by `createCashfreeOrder`. The card shows the
  /// live listing when it still exists and falls back to this snapshot
  /// when the listing was deleted, so an order never degrades to a
  /// bare listing id. Null on orders placed before the snapshot existed.
  final String? listingTitle;
  final String? listingPhotoUrl;
  /// Shiprocket shipment details, written server-side when a paid order
  /// gets a courier booking. Null until the shipment exists.
  final String? awbCode;
  final String? courierName;
  final String? shipmentStatus;
  final String? etd;
  /// The accepted bid this order was placed from, when the order came
  /// from an accepted bid. Lets the Bids & Offers screen match a paid
  /// order back to its offer.
  final String? bidId;
  /// Cashfree payment state: `PENDING`, `SUCCESS`, `FAILED`,
  /// `USER_DROPPED`. Only `SUCCESS` means the buyer paid.
  final String? paymentStatus;
  /// First delivery, stamped server-side when the order first reaches
  /// delivered (courier webhook or admin update). Starts the 72-hour
  /// support window. Null on orders delivered before delivery
  /// timestamps shipped.
  final DateTime? deliveredAt;
  /// Delivery-report state: `open`, `resolved`, or null when no report
  /// was ever filed. Written only by the dispute callables.
  final String? disputeStatus;
  /// Payout record: `pending`, `eligible`, `held`, `paid`, `cancelled`,
  /// or null on orders delivered before settlement tracking shipped.
  final String? settlementStatus;
  /// UPI payment reference recorded by the admin when the payout was
  /// marked sent.
  final String? settlementReference;
  /// `refunded` when a delivery report resolved in the buyer's favor.
  final String? refundStatus;
  /// What the seller receives for this order (price minus commission,
  /// GST, delivery share and TDS), computed server-side at checkout.
  /// Shown to the seller only, on the tracking screen.
  final double? sellerPayout;
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
    this.listingTitle,
    this.listingPhotoUrl,
    this.awbCode,
    this.courierName,
    this.shipmentStatus,
    this.etd,
    this.bidId,
    this.paymentStatus,
    this.deliveredAt,
    this.disputeStatus,
    this.settlementStatus,
    this.settlementReference,
    this.refundStatus,
    this.sellerPayout,
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
/// `listingTitle?`, `listingPhotoUrl?`, `awbCode?`, `courierName?`,
/// `shipmentStatus?`, `etd?`, `paidAt?`, `deliveredAt?`, `disputeStatus?`,
/// `settlementStatus?`, `settlementReference?`, `refundStatus?`,
/// `fees.sellerPayout?`, `createdAt`.
/// Orders are created server-side by the `createCashfreeOrder` callable,
/// clients never write order docs directly. The order doc carries no full
/// listing snapshot, so the nested [Listing] is a minimal placeholder (id
/// only); UI resolves the title/photo via the listing doc when needed,
/// falling back to the purchase-time `listingTitle`/`listingPhotoUrl`
/// snapshot when the listing is gone.
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
      listingTitle: data['listingTitle'] as String?,
      listingPhotoUrl: data['listingPhotoUrl'] as String?,
      awbCode: data['awbCode'] as String?,
      courierName: data['courierName'] as String?,
      shipmentStatus: data['shipmentStatus'] as String?,
      etd: data['etd'] as String?,
      bidId: data['bidId'] as String?,
      paymentStatus: data['paymentStatus'] as String?,
      deliveredAt: data['deliveredAt'] == null
          ? null
          : firestoreDate(data['deliveredAt']),
      disputeStatus: data['disputeStatus'] as String?,
      settlementStatus: data['settlementStatus'] as String?,
      settlementReference: data['settlementReference'] as String?,
      refundStatus: data['refundStatus'] as String?,
      sellerPayout: data['fees'] is Map
          ? ((data['fees'] as Map)['sellerPayout'] as num?)?.toDouble()
          : null,
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['createdAt']),
    );
  }
}
