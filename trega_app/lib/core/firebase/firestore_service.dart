import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../models/bid.dart';
import '../models/category.dart';
import '../models/kyc_verification.dart';
import '../models/listing.dart';
import '../models/order.dart';
import '../models/user.dart';

/// Typed Firestore access for Trega.
///
/// Field names match the canonical Cloud Functions data model
/// (`~/workspace/trega/trega_functions/FIRESTORE_MODEL.md`). The legacy
/// REST client in `core/api/` is DEPRECATED and kept only as a reference —
/// all UI flows go through here.
///
/// Write rules of thumb (enforced by `firestore.rules`):
/// - Listings are created as `draft` via [createListingDraft]; the
///   `onListingCreate` trigger moves them to `pending` for review, and
///   `reviewListing` (admin) flips them to `live`/`rejected`. Clients never
///   write `status` directly.
/// - Bids and orders are written ONLY by Cloud Functions callables
///   ([FunctionsService]) — never `set()`/`add()` from the client.
/// - User docs are created once on sign-in; `role`/`verifiedSeller`/`kycStatus`
///   are server-managed.
class FirestoreService {
  FirestoreService(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _listings =>
      _db.collection('listings');
  CollectionReference<Map<String, dynamic>> get _bids =>
      _db.collection('bids');
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('categories');
  CollectionReference<Map<String, dynamic>> get _kyc =>
      _db.collection('kycVerifications');

  // ── Users ──────────────────────────────────────────────────────────────

  Future<AppUser?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUserFirestore.fromFirestore(doc.data()!, uid);
  }

  /// Creates the user doc on first sign-in (phone, name, role=buyer,
  /// kycStatus=unverified). Never overwrites an existing doc so server-managed
  /// fields (`role`, `verifiedSeller`, `kycStatus`) survive.
  Future<void> ensureUser(String uid, {required String phone}) async {
    final doc = await _users.doc(uid).get();
    if (doc.exists) return;
    await _users.doc(uid).set({
      'phone': phone,
      'name': '',
      'role': 'buyer',
      'kycStatus': 'unverified',
      'verifiedSeller': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<AppUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUserFirestore.fromFirestore(doc.data()!, uid);
    });
  }

  /// Stores/refreshes the device's FCM push token on the user doc so
  /// Cloud Functions can target this device with notifications.
  /// Tokens are kept in an array — one user can have several devices.
  Future<void> saveFcmToken(String uid, String token) async {
    await _users.doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Listings ───────────────────────────────────────────────────────────

  /// Public feed: only `live` listings, newest first.
  Stream<List<Listing>> watchLiveListings({String? currentUid}) {
    return _listings
        .where('status', isEqualTo: 'live')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ListingFirestore.fromFirestore(
                  d.data(),
                  d.id,
                  currentUid: currentUid,
                ))
            .toList());
  }

  Stream<Listing?> watchListing(String id, {String? currentUid}) {
    return _listings.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ListingFirestore.fromFirestore(
        doc.data()!,
        id,
        currentUid: currentUid,
      );
    });
  }

  Stream<List<Listing>> watchCategoryListings(String categoryId,
      {String? currentUid}) {
    return _listings
        .where('status', isEqualTo: 'live')
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ListingFirestore.fromFirestore(
                  d.data(),
                  d.id,
                  currentUid: currentUid,
                ))
            .toList());
  }

  Stream<List<Listing>> watchSellerListings(String sellerId) {
    return _listings
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ListingFirestore.fromFirestore(d.data(), d.id))
            .toList());
  }

  /// Step 1 of the sell flow: creates a `draft` listing and returns its ID.
  /// The `onListingCreate` trigger then moves it to `pending` for review.
  Future<String> createListingDraft({
    required String sellerId,
    required String title,
    required String description,
    required String categoryId,
    required double price,
    required String condition,
  }) async {
    final ref = await _listings.add({
      'sellerId': sellerId,
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'price': price,
      'condition': condition,
      'photos': <String>[],
      'viewCount': 0,
      'likedBy': <String>[],
      'likesCount': 0,
      'status': 'draft',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Step 2 of the sell flow: attaches uploaded photo URLs to the draft.
  Future<void> updateListingMedia(
      String listingId, List<String> photoUrls) async {
    await _listings.doc(listingId).update({'photos': photoUrls});
  }

  Future<void> deleteListing(String listingId) async {
    await _listings.doc(listingId).delete();
  }

  Future<void> incrementViews(String listingId) async {
    await _listings
        .doc(listingId)
        .update({'viewCount': FieldValue.increment(1)});
  }

  Future<void> toggleLike(String listingId, String uid, bool liked) async {
    await _listings.doc(listingId).update({
      'likedBy':
          liked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'likesCount': FieldValue.increment(liked ? -1 : 1),
    });
  }

  /// Listings the user liked. Single-field `arrayContains` query (no
  /// composite index needed); `status == live` is filtered client-side so
  /// sellers' sold/withdrawn items disappear gracefully.
  Stream<List<Listing>> watchWishlist(String uid) {
    return _listings
        .where('likedBy', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ListingFirestore.fromFirestore(
                  d.data(),
                  d.id,
                  currentUid: uid,
                ))
            .where((l) => l.status == ListingStatus.live)
            .toList());
  }

  // ── Bids (read-only; writes go through FunctionsService) ───────────────

  Stream<List<Bid>> watchMyBids(String uid) {
    return _bids
        .where('buyerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BidFirestore.fromFirestore(d.data(), d.id))
            .toList());
  }

  Stream<List<Bid>> watchOffersReceived(String uid) {
    return _bids
        .where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BidFirestore.fromFirestore(d.data(), d.id))
            .toList());
  }

  Stream<List<Bid>> watchListingBids(String listingId) {
    return _bids
        .where('listingId', isEqualTo: listingId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BidFirestore.fromFirestore(d.data(), d.id))
            .toList());
  }

  // ── Orders (read-only; written by createCashfreeOrder) ────────────────

  Stream<List<Order>> watchMyOrders(String uid) {
    return _orders
        .where('buyerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrderFirestore.fromFirestore(d.data(), d.id))
            .toList());
  }

  Stream<List<Order>> watchSellerOrders(String uid) {
    return _orders
        .where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrderFirestore.fromFirestore(d.data(), d.id))
            .toList());
  }

  Stream<Order?> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return OrderFirestore.fromFirestore(doc.data()!, orderId);
    });
  }

  // ── Categories ─────────────────────────────────────────────────────────

  Stream<List<Category>> watchCategories() {
    return _categories
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Category.fromFirestore(d.data(), d.id))
            .toList());
  }

  Future<Category?> getCategory(String id) async {
    final doc = await _categories.doc(id).get();
    if (!doc.exists) return null;
    return Category.fromFirestore(doc.data()!, id);
  }

  // ── KYC ────────────────────────────────────────────────────────────────

  Stream<KycVerification> watchKyc(String uid) {
    return _kyc.doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return KycVerification(uid: uid);
      }
      return KycVerification.fromFirestore(doc.data()!, uid);
    });
  }
}
