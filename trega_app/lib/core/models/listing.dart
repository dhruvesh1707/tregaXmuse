import 'firestore_convert.dart';
import 'product.dart';
import 'user.dart';

/// Lifecycle of a listing, matching the Cloud Functions data model.
///
/// Clients create listings as [draft]; the `onListingCreate` trigger moves
/// them to [pending] for team review, and `reviewListing` (admin) flips them
/// to [live] or [rejected]. Clients never write status directly.
enum ListingStatus {
  draft,
  pending,
  live,
  sold,
  rejected,
}

extension ListingStatusLabel on ListingStatus {
  String get label {
    switch (this) {
      case ListingStatus.draft:
        return 'Draft';
      case ListingStatus.pending:
        return 'In review';
      case ListingStatus.live:
        return 'Live';
      case ListingStatus.sold:
        return 'Sold';
      case ListingStatus.rejected:
        return 'Rejected';
    }
  }

  static ListingStatus fromJson(String value) {
    return ListingStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ListingStatus.draft,
    );
  }

  /// Firestore wire value is the lowercase enum name (identical here).
  static ListingStatus fromWire(String value) => fromJson(value);
}

/// A product listed for sale by a seller, with pricing and sale settings.
class Listing {
  final String id;
  final Product product;
  final AppUser seller;
  final double price;
  final bool negotiable;
  final bool biddingEnabled;
  final ListingStatus status;
  final DateTime createdAt;
  final int viewsCount;
  final int likesCount;
  final bool isLiked;

  const Listing({
    required this.id,
    required this.product,
    required this.seller,
    required this.price,
    this.negotiable = true,
    this.biddingEnabled = false,
    this.status = ListingStatus.live,
    required this.createdAt,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.isLiked = false,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      id: json['id'] as String,
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      seller: AppUser.fromJson(json['seller'] as Map<String, dynamic>),
      price: (json['price'] as num).toDouble(),
      negotiable: json['negotiable'] as bool? ?? true,
      biddingEnabled: json['bidding_enabled'] as bool? ?? false,
      status: ListingStatusLabel.fromJson(json['status'] as String? ?? ''),
      createdAt: DateTime.parse(json['created_at'] as String),
      viewsCount: json['views_count'] as int? ?? 0,
      likesCount: json['likes_count'] as int? ?? 0,
      isLiked: json['is_liked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'seller': seller.toJson(),
      'price': price,
      'negotiable': negotiable,
      'bidding_enabled': biddingEnabled,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'views_count': viewsCount,
      'likes_count': likesCount,
      'is_liked': isLiked,
    };
  }

  Listing copyWith({bool? isLiked, int? likesCount, ListingStatus? status}) {
    return Listing(
      id: id,
      product: product,
      seller: seller,
      price: price,
      negotiable: negotiable,
      biddingEnabled: biddingEnabled,
      status: status ?? this.status,
      createdAt: createdAt,
      viewsCount: viewsCount,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

/// Firestore serialization for `listings/{listingId}` documents.
///
/// Field names match the canonical Cloud Functions data model
/// (`~/workspace/trega/trega_functions/FIRESTORE_MODEL.md`):
/// `sellerId`, `title`, `description`, `categoryId`, `price`,
/// `condition` (`brand_new`…), `photos[]`, `videoUrl?`, `status`
/// (`draft`→`pending`→`live`→`sold`/`rejected`), `viewCount`, `createdAt`.
///
/// Additive (client-managed) fields not in the canonical doc:
/// `likedBy[]` / `likesCount` (wishlist). `negotiable`/`biddingEnabled` are
/// v1 client defaults (true) and are NOT persisted.
///
/// [fromFirestore] rebuilds the nested [Product]/[AppUser] the UI expects.
extension ListingFirestore on Listing {
  static Listing fromFirestore(
    Map<String, dynamic> data,
    String docId, {
    String? currentUid,
  }) {
    final likedBy = firestoreStringList(data['likedBy']);
    return Listing(
      id: docId,
      product: Product(
        id: docId,
        title: data['title'] as String? ?? '',
        description: data['description'] as String? ?? '',
        categoryId: data['categoryId'] as String? ?? '',
        condition:
            ConditionLabel.fromWire(data['condition'] as String? ?? ''),
        imageUrls: firestoreStringList(data['photos']),
        videoUrl: data['videoUrl'] as String?,
        specs: const {},
      ),
      seller: AppUser(
        id: data['sellerId'] as String? ?? '',
        name: '',
        phone: '',
      ),
      price: (data['price'] as num? ?? 0).toDouble(),
      negotiable: true,
      biddingEnabled: true,
      status: ListingStatusLabel.fromWire(data['status'] as String? ?? ''),
      createdAt: firestoreDate(data['createdAt']),
      viewsCount: data['viewCount'] as int? ?? 0,
      likesCount: data['likesCount'] as int? ?? 0,
      isLiked: currentUid != null && likedBy.contains(currentUid),
    );
  }

  /// Writes a new listing document. Callers must set `status: 'draft'` —
  /// the `onListingCreate` trigger moves it to `pending` for review.
  /// Use [FirestoreService.createListingDraft] instead of calling this
  /// directly so server timestamps and the draft status are enforced.
  Map<String, dynamic> toFirestore() {
    return {
      'sellerId': seller.id,
      'title': product.title,
      'description': product.description,
      'categoryId': product.categoryId,
      'price': price,
      'condition': product.condition.wireValue,
      'photos': product.imageUrls,
      'videoUrl': product.videoUrl,
      'viewCount': 0,
      'likedBy': <String>[],
      'likesCount': 0,
    };
  }
}
