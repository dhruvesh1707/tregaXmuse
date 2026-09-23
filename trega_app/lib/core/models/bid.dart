import 'firestore_convert.dart';

/// A buyer's bid or offer on a listing.
///
/// Note: Trega deliberately has no buyer↔seller chat. Negotiation happens
/// through structured bids/offers with accept / reject / counter actions,
/// all executed server-side via the `placeBid` / `acceptBid` callables.
enum BidStatus {
  open,
  accepted,
  rejected,
  expired,
  countered,
}

extension BidStatusLabel on BidStatus {
  String get label {
    switch (this) {
      case BidStatus.open:
        return 'Open';
      case BidStatus.accepted:
        return 'Accepted';
      case BidStatus.rejected:
        return 'Rejected';
      case BidStatus.expired:
        return 'Expired';
      case BidStatus.countered:
        return 'Countered';
    }
  }

  static BidStatus fromJson(String value) {
    return BidStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => BidStatus.open,
    );
  }

  /// Firestore wire value is the lowercase enum name (identical here).
  static BidStatus fromWire(String value) => fromJson(value);
}

class Bid {
  final String id;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final double amount;
  final double? counterAmount;
  final BidStatus status;
  final DateTime createdAt;

  /// Display-only joins populated by the UI (not stored on the bid doc).
  final String? buyerName;
  final String? listingTitle;

  const Bid({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.amount,
    this.counterAmount,
    this.status = BidStatus.open,
    required this.createdAt,
    this.buyerName,
    this.listingTitle,
  });

  factory Bid.fromJson(Map<String, dynamic> json) {
    return Bid(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      buyerId: json['buyer_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      amount: (json['amount'] as num).toDouble(),
      counterAmount: (json['counter_amount'] as num?)?.toDouble(),
      status: BidStatusLabel.fromJson(json['status'] as String? ?? ''),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'listing_id': listingId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': amount,
      'counter_amount': counterAmount,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Bid copyWith({String? buyerName, String? listingTitle}) {
    return Bid(
      id: id,
      listingId: listingId,
      buyerId: buyerId,
      sellerId: sellerId,
      amount: amount,
      counterAmount: counterAmount,
      status: status,
      createdAt: createdAt,
      buyerName: buyerName ?? this.buyerName,
      listingTitle: listingTitle ?? this.listingTitle,
    );
  }
}

/// Firestore deserialization for `bids/{bidId}` documents.
///
/// Canonical fields: `listingId`, `buyerId`, `sellerId`, `amount`,
/// `status` (`open`|`accepted`|`rejected`|`expired`|`countered`),
/// `counterAmount?`, `createdAt`. Clients never write bid docs directly —
/// bids are created via the `placeBid` callable and resolved via
/// `acceptBid`; see [FunctionsService].
extension BidFirestore on Bid {
  static Bid fromFirestore(Map<String, dynamic> data, String docId) {
    return Bid(
      id: docId,
      listingId: data['listingId'] as String? ?? '',
      buyerId: data['buyerId'] as String? ?? '',
      sellerId: data['sellerId'] as String? ?? '',
      amount: (data['amount'] as num? ?? 0).toDouble(),
      counterAmount: (data['counterAmount'] as num?)?.toDouble(),
      status: BidStatusLabel.fromWire(data['status'] as String? ?? ''),
      createdAt: firestoreDate(data['createdAt']),
    );
  }
}

