import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_providers.dart';

/// Marketplace pricing, owned by the console `config/fees` doc
/// (public read) over bundled defaults — mirroring `config/delivery`.
///
/// Launch month ("Zero Fee Launch"): 0% seller commission + 0% buyer
/// protection fee. The only charge is the fixed delivery fee (₹99),
/// split 50-50 between buyer and seller. Month 2+: 3% seller / 5% buyer.
///
/// The server recomputes everything authoritatively inside
/// `createCashfreeOrder`; [quote] is display-only — the app never sends
/// money based on its own math.
class FeeConfig {
  final bool promoActive;
  final double sellerPct;
  final double buyerPct;

  /// Fixed delivery fee in INR — split 50-50 buyer/seller.
  final double deliveryFlat;

  /// GST percent applied on the platform fees (18%).
  final double gstPct;

  /// Bundled defaults — used until (and unless) `config/fees` exists.
  /// Mirrors the server fallback: the Zero Fee Launch.
  static const FeeConfig defaults = FeeConfig(
    promoActive: true,
    sellerPct: 0,
    buyerPct: 0,
    deliveryFlat: 99,
    gstPct: 18,
  );

  const FeeConfig({
    required this.promoActive,
    required this.sellerPct,
    required this.buyerPct,
    required this.deliveryFlat,
    required this.gstPct,
  });

  factory FeeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    double numOr(dynamic v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    return FeeConfig(
      promoActive: map['promoActive'] == true,
      sellerPct: numOr(map['sellerPct'], defaults.sellerPct),
      buyerPct: numOr(map['buyerPct'], defaults.buyerPct),
      deliveryFlat: numOr(map['deliveryFlat'], defaults.deliveryFlat),
      gstPct: numOr(map['gstPct'], defaults.gstPct),
    );
  }

  /// Buyer-side price breakdown for display. The server is authoritative.
  FeeQuote quote(double price) {
    final buyerFee = (price * buyerPct / 100).roundToDouble();
    final buyerFeeGst = (buyerFee * gstPct / 100).roundToDouble();
    // Any odd paise of the 50-50 split goes to the buyer.
    final deliveryBuyerShare = (deliveryFlat * 50).ceilToDouble() / 100;
    final total = price + buyerFee + buyerFeeGst + deliveryBuyerShare;
    return FeeQuote(
      price: price,
      buyerFee: buyerFee,
      buyerFeeGst: buyerFeeGst,
      deliveryFlat: deliveryFlat,
      deliveryBuyerShare: deliveryBuyerShare,
      buyerTotal: (total * 100).roundToDouble() / 100,
    );
  }
}

/// What the buyer sees on the checkout screen.
class FeeQuote {
  final double price;
  final double buyerFee;
  final double buyerFeeGst;
  final double deliveryFlat;
  final double deliveryBuyerShare;
  final double buyerTotal;

  const FeeQuote({
    required this.price,
    required this.buyerFee,
    required this.buyerFeeGst,
    required this.deliveryFlat,
    required this.deliveryBuyerShare,
    required this.buyerTotal,
  });
}

/// Live fee config: the `config/fees` doc over bundled defaults, so the
/// team can flip from the Zero Fee Launch to standard pricing (or retune
/// the delivery fee) from the Firebase console with no app update.
final feeConfigProvider = StreamProvider<FeeConfig>(
  (ref) => ref
      .watch(firestoreServiceProvider)
      .watchFeeConfig()
      .map(FeeConfig.fromMap),
);
