import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';
import 'firestore_service.dart';
import 'functions_service.dart';
import 'storage_service.dart';

/// Central Riverpod providers for Firebase SDK singletons.
///
/// All feature code should depend on these providers (or the typed services
/// in this folder) — never construct Firebase instances directly in widgets.
final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firebaseStorageProvider =
    Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final firebaseMessagingProvider =
    Provider<FirebaseMessaging>((ref) => FirebaseMessaging.instance);

final cloudFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: 'asia-south1'),
);

/// Stream of the current Firebase [User]; null when signed out.
/// Used to gate the app shell (splash → onboarding/auth vs home).
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

/// Current Firebase uid, or null when signed out.
final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(firebaseAuthProvider).currentUser?.uid,
);

// ------------------------------------------------------------ typed services

/// Typed Firestore access (collections: users, listings, bids, orders,
/// categories, kycVerifications).
final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(ref.watch(firestoreProvider)),
);

/// Phone-OTP auth backed by Firebase Auth.
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreServiceProvider),
  ),
);

/// Callables for server-side integrations (BulkPe KYC, Cashfree payments).
/// Secrets stay in Cloud Functions config — never in the app.
final functionsServiceProvider = Provider<FunctionsService>(
  (ref) => FunctionsService(ref.watch(cloudFunctionsProvider)),
);

/// Media uploads (listing photos, avatars).
final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(ref.watch(firebaseStorageProvider)),
);
