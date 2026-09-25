import 'package:cloud_functions/cloud_functions.dart';

/// Extracts a human-readable message from a callable failure.
///
/// Firebase wraps server `HttpsError`s in [FirebaseFunctionsException]
/// carrying the exact message the function threw — surface that instead of
/// a generic "try again" so the user knows what actually went wrong.
String functionsErrorMessage(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
  if (e is FirebaseFunctionsException) {
    final msg = e.message;
    if (msg != null && msg.isNotEmpty) return msg;
  }
  return fallback;
}

/// Secure bridge to server-side integrations.
///
/// The app NEVER talks to BulkPe or Cashfree directly — API tokens/secrets
/// live only in Cloud Functions secrets (`firebase functions:secrets:set`:
/// `BULKPE_API_TOKEN`, `CASHFREE_APP_ID`, `CASHFREE_SECRET_KEY`,
/// `CASHFREE_ENV`). These callables invoke the deployed functions in
/// `~/workspace/trega/trega_functions/` (region `asia-south1`).
///
/// Callable names (exact, must match `trega_functions/src/index.ts`):
/// - `requestAadhaarOtp` ({aadhaarNumber}) -> {success, refId, message}
/// - `verifyAadhaarOtp`  ({refId, otp}) -> {success, verified, name?, dob?, ...}
/// - `createCashfreeOrder` ({listingId?, bidId?, customerPhone, deliveryAddress?})
///   -> {success, paymentSessionId, cfOrderId, orderId}
/// - `placeBid` ({listingId, amount}) -> {success, bidId}
/// - `acceptBid` ({bidId}) -> {success}
/// - `rejectBid` ({bidId}) -> {success}
/// - `cancelAcceptance` ({bidId}) -> {success}
/// - `deleteAccount` () -> {deleted} — wipes the account completely
/// - `reviewListing` ({listingId, approve, reason?}) -> {success, status}
///   (admin custom claim only)
class FunctionsService {
  FunctionsService(this._functions);

  final FirebaseFunctions _functions;

  // ------------------------------------------------------------ KYC (BulkPe)

  /// Step 1 of Aadhaar verification: sends an OTP to the Aadhaar-linked
  /// mobile number. Returns the BulkPe `refId` to use in step 2.
  ///
  /// The Aadhaar number is sent only to our own Cloud Function over TLS;
  /// it is never persisted in Firestore.
  Future<String> requestAadhaarOtp(String aadhaarNumber) async {
    final result = await _functions
        .httpsCallable('requestAadhaarOtp')
        .call({'aadhaarNumber': aadhaarNumber});
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['refId'] as String;
  }

  /// Step 2: verifies the OTP against BulkPe. Returns the verified
  /// demographic fields (name, dob, gender, address) on success.
  Future<Map<String, dynamic>> verifyAadhaarOtp(
      String refId, String otp,) async {
    final result = await _functions
        .httpsCallable('verifyAadhaarOtp')
        .call({'refId': refId, 'otp': otp});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // -------------------------------------------------------- Cashfree orders

  /// Creates a Cashfree payment session for a listing (optionally via an
  /// accepted bid). The server reads the authoritative price from Firestore
  /// and creates the `orders/{orderId}` doc with `paymentStatus: 'PENDING'`.
  /// Returns `paymentSessionId` for the Cashfree SDK + the new `orderId`.
  Future<Map<String, dynamic>> createCashfreeOrder({
    String? listingId,
    String? bidId,
    required String customerPhone,
    Map<String, String>? deliveryAddress,
  }) async {
    final result =
        await _functions.httpsCallable('createCashfreeOrder').call({
      if (listingId != null) 'listingId': listingId,
      if (bidId != null) 'bidId': bidId,
      'customerPhone': customerPhone,
      if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Verifies a payment server-side. Call after the Cashfree SDK reports
  /// success — the app must treat the order as paid ONLY when this returns
  /// `paymentStatus: 'SUCCESS'`. The server asks Cashfree's Orders API
  /// directly with the secret key; the SDK's on-device callback alone is
  /// never proof that money moved.
  Future<Map<String, dynamic>> verifyPayment({required String orderId}) async {
    final result = await _functions
        .httpsCallable('verifyPayment')
        .call({'orderId': orderId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ------------------------------------------------------------ bids/offers

  /// Places a bid on a live listing. Server validates: not the seller,
  /// listing is live, amount > 0.
  Future<String> placeBid({
    required String listingId,
    required double amount,
  }) async {
    final result = await _functions
        .httpsCallable('placeBid')
        .call({'listingId': listingId, 'amount': amount});
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['bidId'] as String;
  }

  /// Accepts an offer (seller only). Server marks the offer accepted,
  /// rejects the other open offers and reserves the listing for the winner
  /// (`listings/{id}.acceptedBidId`) until they pay.
  Future<void> acceptBid({required String bidId}) async {
    await _functions.httpsCallable('acceptBid').call({'bidId': bidId});
  }

  /// Rejects one open offer (seller only). The buyer is notified and may
  /// send a new offer afterwards.
  Future<void> rejectBid({required String bidId}) async {
    await _functions.httpsCallable('rejectBid').call({'bidId': bidId});
  }

  /// Cancels an accepted offer (seller only, e.g. the buyer never paid).
  /// The listing opens up for offers again.
  Future<void> cancelAcceptance({required String bidId}) async {
    await _functions.httpsCallable('cancelAcceptance').call({'bidId': bidId});
  }

  // ---------------------------------------------------------- account

  /// Deletes the caller's account and every record tied to it, server-side:
  /// profile, listings (+ photos), bids, orders, reviews, reports,
  /// notifications, KYC, and the Auth user itself. No undo — the UI
  /// confirms explicitly before calling this.
  Future<void> deleteAccount() async {
    await _functions.httpsCallable('deleteAccount').call();
  }
}
