import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/category.dart';
import '../../../core/models/listing.dart';
import '../../../core/models/product.dart';
import '../../../core/models/user.dart';

/// Live marketplace feed with stale-while-revalidate local cache.
///
/// Shows the last-known listings instantly — even on a cold start — then
/// refreshes from Firestore in the background. Every fresh snapshot is
/// persisted to disk, so going back to the feed (or reopening the app)
/// never flashes an empty state again.
final liveListingsProvider =
    AsyncNotifierProvider<LiveListingsNotifier, List<Listing>>(
  LiveListingsNotifier.new,
);

class LiveListingsNotifier extends AsyncNotifier<List<Listing>> {
  static const _cacheKey = 'trega_cache_live_listings_v1';
  StreamSubscription<List<Listing>>? _sub;

  @override
  Future<List<Listing>> build() async {
    // Never auto-dispose: the feed stays warm for the app's lifetime.
    ref.keepAlive();

    final prefs = await SharedPreferences.getInstance();
    var seed = const <Listing>[];
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        seed = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(_listingFromCacheJson)
            .toList();
      } catch (_) {
        // Corrupt cache — start empty and let the stream refill it.
      }
    }

    final service = ref.watch(firestoreServiceProvider);
    final uid = ref.watch(currentUidProvider);
    final stream = service.watchLiveListings(currentUid: uid);
    _sub?.cancel();
    _sub = stream.listen(
      (listings) {
        state = AsyncData(listings);
        unawaited(_persist(listings));
      },
      onError: (Object e, StackTrace st) {
        // Offline with a warm cache → keep showing it; without one,
        // surface the error so the UI can render its error state.
        if (seed.isEmpty) state = AsyncError(e, st);
      },
    );
    ref.onDispose(() => _sub?.cancel());

    if (seed.isNotEmpty) return seed;
    // No cache yet: hold the loading state until the first live snapshot
    // (Firestore serves its own disk cache first, so this stays fast).
    final first = await stream.first;
    unawaited(_persist(first));
    return first;
  }

  Future<void> _persist(List<Listing> listings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(listings.map(_listingToCacheJson).toList()),
      );
    } catch (_) {
      // Cache writes must never break the feed.
    }
  }

  Map<String, dynamic> _listingToCacheJson(Listing l) => {
        'id': l.id,
        'title': l.product.title,
        'description': l.product.description,
        'categoryId': l.product.categoryId,
        'condition': l.product.condition.wireValue,
        'photos': l.product.imageUrls,
        'sellerId': l.seller.id,
        'price': l.price,
        'negotiable': l.negotiable,
        'status': l.status.name,
        'createdAt': l.createdAt.toIso8601String(),
        'viewCount': l.viewsCount,
        'likesCount': l.likesCount,
        'isLiked': l.isLiked,
        'city': l.city,
      };

  Listing _listingFromCacheJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return Listing(
      id: id,
      product: Product(
        id: id,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        categoryId: j['categoryId'] as String? ?? '',
        condition:
            ConditionLabel.fromWire(j['condition'] as String? ?? ''),
        imageUrls:
            (j['photos'] as List?)?.whereType<String>().toList() ??
                const [],
      ),
      seller: AppUser(
        id: j['sellerId'] as String? ?? '',
        name: '',
        phone: '',
      ),
      price: (j['price'] as num? ?? 0).toDouble(),
      negotiable: j['negotiable'] as bool? ?? true,
      status: ListingStatusLabel.fromWire(j['status'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ??
              DateTime.now(),
      viewsCount: j['viewCount'] as int? ?? 0,
      likesCount: j['likesCount'] as int? ?? 0,
      isLiked: j['isLiked'] as bool? ?? false,
      city: j['city'] as String? ?? '',
    );
  }
}

/// Marketplace categories from Firestore (`categories` collection).
final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(firestoreServiceProvider).watchCategories();
});

/// Single listing detail stream.
final listingDetailProvider =
    StreamProvider.family<Listing?, String>((ref, listingId) {
  final uid = ref.watch(currentUidProvider);
  return ref
      .watch(firestoreServiceProvider)
      .watchListing(listingId, currentUid: uid);
});

/// Listings in one category.
final categoryListingsProvider =
    StreamProvider.family<List<Listing>, String>((ref, categoryId) {
  final uid = ref.watch(currentUidProvider);
  return ref
      .watch(firestoreServiceProvider)
      .watchCategoryListings(categoryId, currentUid: uid);
});

/// Unread in-app notification count for the app-bar bell badge.
///
/// Reads the live inbox (`users/{uid}/notifications`) so the badge always
/// matches reality — 0 (or signed out) means no badge at all.
final unreadNotificationsProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(0);
  return ref
      .watch(firestoreServiceProvider)
      .watchNotifications(user.uid)
      .map((items) => items.where((n) => !n.read).length);
});
