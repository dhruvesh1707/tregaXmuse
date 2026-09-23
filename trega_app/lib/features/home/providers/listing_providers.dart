import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/category.dart';
import '../../../core/models/listing.dart';

/// Live marketplace feed (listings with `status == live`).
///
/// When Firestore is unreachable (e.g. `firebase_options.dart` not yet
/// generated), consumers fall back to `SampleData` and show a demo banner —
/// see [HomeScreen].
final liveListingsProvider = StreamProvider<List<Listing>>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  final uid = ref.watch(currentUidProvider);
  return service.watchLiveListings(currentUid: uid);
});

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
