import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'firestore_service.dart';

/// Phone-OTP authentication backed by Firebase Auth.
///
/// Flow:
///  1. [sendOtp] — Firebase sends an SMS to `+91 <phone>`. The returned
///     verificationId is held by the UI (or this service) for step 2.
///  2. [verifyOtp] — builds a [PhoneAuthCredential] from verificationId + the
///     6-digit SMS code and signs in. On first sign-in a `users/{uid}` doc is
///     created via [FirestoreService.ensureUser].
///
/// Web note: on Flutter web, [verifyPhoneNumber] needs a reCAPTCHA verifier.
/// The Firebase JS SDK handles it automatically for invisible reCAPTCHA as
/// long as the site domain is allow-listed in the Firebase console
/// (Authentication → Settings → Authorized domains). No app code changes
/// needed, but `flutterfire configure` must include the web app.
class AuthService {
  AuthService({
    required FirebaseAuth auth,
    required FirestoreService firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirestoreService _firestore;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Sends an OTP to the given 10-digit Indian phone number.
  ///
  /// Calls [onCodeSent] with the verificationId when the SMS is dispatched.
  /// [onAutoVerified] fires on Android auto-retrieval / instant verification.
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    final fullPhone = '+91$phoneNumber';
    await _auth.verifyPhoneNumber(
      phoneNumber: fullPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        // Android auto-retrieval / instant verification path.
        onAutoVerified?.call(credential);
      },
      verificationFailed: (e) {
        debugPrint('Trega phone auth failed: ${e.code} ${e.message}');
        onError(_friendlyError(e));
      },
      codeSent: (verificationId, resendToken) {
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        // SMS not auto-retrieved in time — user types the code manually.
        debugPrint('Trega auto-retrieval timeout for $verificationId');
      },
    );
  }

  /// Verifies the SMS code and signs the user in, creating the Firestore
  /// user document on first login.
  Future<AppUser> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String phoneNumber,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _signInWithCredential(
      credential,
      phoneNumber: phoneNumber,
    );
  }

  /// Signs in with an auto-retrieved credential (Android).
  Future<AppUser> signInWithAutoCredential(
    PhoneAuthCredential credential, {
    required String phoneNumber,
  }) =>
      _signInWithCredential(credential, phoneNumber: phoneNumber);

  Future<AppUser> _signInWithCredential(
    PhoneAuthCredential credential, {
    required String phoneNumber,
  }) async {
    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw StateError('Firebase sign-in returned no user.');
    }

    final appUser = AppUser(
      id: firebaseUser.uid,
      name: firebaseUser.displayName ?? '',
      phone: phoneNumber,
      avatarUrl: firebaseUser.photoURL,
      joinedAt: DateTime.now(),
    );

    // Create the users/{uid} doc on first sign-in; never overwrite existing.
    await _firestore.ensureUser(appUser.id, phone: appUser.phone);
    return appUser;
  }

  Future<void> signOut() => _auth.signOut();

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid. Please check and retry.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      default:
        return 'Could not send OTP (${e.code}). Please try again.';
    }
  }
}
