import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// SharedPreferences keys for the in-flight OTP attempt. If the OS kills
  /// the app mid-verification (e.g. during the iOS reCAPTCHA round-trip),
  /// the phone screen restores the OTP-entry state instead of dropping the
  /// user back at the phone-number step.
  static const _kPendingVerificationId = 'trega_pending_verification_id';
  static const _kPendingPhone = 'trega_pending_phone';
  static const _kPendingTs = 'trega_pending_ts';

  /// How long a persisted OTP attempt stays restorable (Firebase SMS codes
  /// live ~2 minutes; we allow a generous window for slow round-trips).
  static const _pendingTtl = Duration(minutes: 10);

  /// Persists the phone number the moment the user taps "Send OTP" —
  /// *before* Firebase runs. On iOS the reCAPTCHA can appear immediately,
  /// and if the OS kills the app while it is up there is no verificationId
  /// yet; the persisted phone still lets the UI offer a one-tap retry.
  static Future<void> savePendingAttempt({
    required String phoneNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingPhone, phoneNumber);
    await prefs.setInt(
        _kPendingTs, DateTime.now().millisecondsSinceEpoch,);
  }

  /// Persists an in-flight OTP attempt. Called when Firebase reports
  /// `codeSent` (adds the verificationId to the attempt saved by
  /// [savePendingAttempt]).
  static Future<void> savePendingVerification({
    required String verificationId,
    required String phoneNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingVerificationId, verificationId);
    await prefs.setString(_kPendingPhone, phoneNumber);
    await prefs.setInt(
        _kPendingTs, DateTime.now().millisecondsSinceEpoch,);
  }

  /// Returns the persisted attempt, or `null` when there is none or it is
  /// older than [_pendingTtl]. [verificationId] is null when the app was
  /// killed before Firebase reported `codeSent` (e.g. during the iOS
  /// reCAPTCHA); the phone number is still available so the UI can offer a
  /// one-tap retry instead of a blank phone field.
  static Future<({String? verificationId, String phoneNumber})?>
      loadPendingVerification() async {
    final prefs = await SharedPreferences.getInstance();
    final verificationId = prefs.getString(_kPendingVerificationId);
    final phone = prefs.getString(_kPendingPhone);
    final ts = prefs.getInt(_kPendingTs);
    if (phone == null || ts == null) return null;
    final age =
        DateTime.now().millisecondsSinceEpoch - ts;
    if (age > _pendingTtl.inMilliseconds) {
      await clearPendingVerification();
      return null;
    }
    return (verificationId: verificationId, phoneNumber: phone);
  }

  static Future<void> clearPendingVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingVerificationId);
    await prefs.remove(_kPendingPhone);
    await prefs.remove(_kPendingTs);
  }

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
  ///
  /// Returns the signed-in user plus whether this was their first-ever
  /// sign-in (so the UI can route new users through profile setup).
  Future<({AppUser user, bool isNewUser})> verifyOtp({
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
  Future<({AppUser user, bool isNewUser})> signInWithAutoCredential(
    PhoneAuthCredential credential, {
    required String phoneNumber,
  }) =>
      _signInWithCredential(credential, phoneNumber: phoneNumber);

  Future<({AppUser user, bool isNewUser})> _signInWithCredential(
    PhoneAuthCredential credential, {
    required String phoneNumber,
  }) async {
    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw StateError('Firebase sign-in returned no user.');
    }

    // Create the users/{uid} doc on first sign-in; never overwrite existing.
    final isNewUser =
        await _firestore.ensureUser(firebaseUser.uid, phone: phoneNumber);
    // Register this device for push notifications (best-effort; never
    // blocks sign-in). Token refreshes are picked up for the session.
    unawaited(_registerFcmToken(firebaseUser.uid));

    final stored = await _firestore.getUser(firebaseUser.uid);
    final appUser = stored ??
        AppUser(
          id: firebaseUser.uid,
          name: firebaseUser.displayName ?? '',
          phone: phoneNumber,
          avatarUrl: firebaseUser.photoURL,
          joinedAt: DateTime.now(),
        );
    await clearPendingVerification();
    return (user: appUser, isNewUser: isNewUser);
  }

  /// Saves the FCM device token to the user doc. Skipped on web (needs a
  /// VAPID key) — push targets Android/iOS in v1.
  static bool _fcmRefreshHooked = false;

  Future<void> _registerFcmToken(String uid) async {
    try {
      if (kIsWeb) return;
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await _firestore.saveFcmToken(uid, token);
      }
      if (!_fcmRefreshHooked) {
        _fcmRefreshHooked = true;
        messaging.onTokenRefresh.listen((t) {
          _firestore.saveFcmToken(uid, t).catchError((_) {});
        });
      }
    } catch (e) {
      debugPrint('FCM token registration skipped: $e');
    }
  }

  Future<void> signOut() async {
    await clearPendingVerification();
    await _auth.signOut();
  }

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
