import 'package:cloud_functions/cloud_functions.dart';

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
/// - `createCashfreeOrder` ({listingId, bidId?, customerPhone})
///   -> {success, paymentSessionId, cfOrderId, orderId}
/// - `placeBid` ({listingId, amount}) -> {success, bidId}
/// - `acceptBid` ({bidId}) -> {success, orderId?}
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
    required String listingId,
    String? bidId,
    required String customerPhone,
  }) async {
    final result =
        await _functions.httpsCallable('createCashfreeOrder').call({
      'listingId': listingId,
      if (bidId != null) 'bidId': bidId,
      'customerPhone': customerPhone,
    });
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

  /// Accepts a bid (seller only). Server marks the bid accepted, rejects the
  /// others, and moves the listing to `sold`.
  Future<void> acceptBid({required String bidId}) async {
    await _functions.httpsCallable('acceptBid').call({'bidId': bidId});
  }
}
