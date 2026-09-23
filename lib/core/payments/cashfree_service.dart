import 'package:flutter_cashfree_pg_sdk/flutter_cashfree_pg_sdk.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around the Cashfree PG SDK (drop checkout).
///
/// Flow:
///  1. Our `createCashfreeOrder` callable creates the order server-side and
///     returns `{paymentSessionId, orderId, cfOrderRef?}`.
///  2. [pay] opens the Cashfree checkout sheet with that session.
///  3. The SDK callback only drives UI — payment truth always comes from
///     the `cashfreeWebhook` function flipping the order's `paymentStatus`.
///
/// The SDK needs the *merchant* order id that was sent to Cashfree
/// (`trega_<orderId>`, see `trega_functions/src/payments.ts`), not the
/// Firestore doc id and not Cashfree's numeric `cf_order_id`.
class CashfreeService {
  /// Must match the backend `CASHFREE_ENV` secret (currently production).
  /// Sandbox and production sessions are NOT interchangeable.
  static const CFEnvironment environment = CFEnvironment.PRODUCTION;

  /// Opens the Cashfree drop-checkout sheet.
  ///
  /// [onVerified] fires when the SDK reports the payment journey finished
  /// for [cfOrderId] — the app should then confirm the order via Firestore
  /// (the webhook updates `paymentStatus` asynchronously).
  /// [onError] fires on failure or cancellation with a readable message.
  ///
  /// Note: the SDK's web implementation is a stub — real payments must be
  /// tested on Android/iOS, never on Flutter web.
  void pay({
    required String cfOrderId,
    required String paymentSessionId,
    required void Function(String cfOrderId) onVerified,
    required void Function(String message, String cfOrderId) onError,
  }) {
    try {
      final session = CFSessionBuilder()
          .setEnvironment(environment)
          .setOrderId(cfOrderId)
          .setPaymentSessionId(paymentSessionId)
          .build();
      final payment =
          CFDropCheckoutPaymentBuilder().setSession(session).build();
      CFPaymentGatewayService().setCallback(
        (orderId) => onVerified(orderId),
        (error, orderId) => onError(error.getMessage(), orderId),
      );
      CFPaymentGatewayService().doPayment(payment);
    } on CFException catch (e) {
      debugPrint('Cashfree SDK error: ${e.message}');
      onError(e.message, cfOrderId);
    } catch (e) {
      debugPrint('Cashfree pay failed: $e');
      onError('Could not open checkout. Try again.', cfOrderId);
    }
  }
}
