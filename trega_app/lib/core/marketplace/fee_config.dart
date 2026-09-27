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
    // Seller-side mirror of the server's quoteFees — lets checkout detect
    // up front when an order can never be placed: with the flat delivery
    // fee split 50-50, a price below the seller's delivery share (+TDS)
    // would leave the seller with a negative payout.
    final sellerCommission = (price * sellerPct / 100).roundToDouble();
    final sellerCommissionGst =
        (sellerCommission * gstPct / 100).roundToDouble();
    final deliverySellerShare =
        ((deliveryFlat - deliveryBuyerShare) * 100).roundToDouble() / 100;
    final tds = (price / 100).roundToDouble();
    final sellerPayout = price -
        sellerCommission -
        sellerCommissionGst -
        deliverySellerShare -
        tds;
    return FeeQuote(
      price: price,
      buyerFee: buyerFee,
      buyerFeeGst: buyerFeeGst,
      deliveryFlat: deliveryFlat,
      deliveryBuyerShare: deliveryBuyerShare,
      deliverySellerShare: deliverySellerShare,
      buyerTotal: (total * 100).roundToDouble() / 100,
      sellerPayout: sellerPayout,
    );
  }

  /// Smallest whole-rupee listing price at which the seller's payout stays
  /// positive — i.e. the price covers the seller's delivery share,
  /// commission and TDS. Computed from the live config so it stays correct
  /// when the console flips pricing (Zero Fee Launch → standard fees).
  /// Listings below this can never be checked out.
  int get minListPrice {
    var p = 1;
    while (p < 1000000 && quote(p.toDouble()).sellerPayout <= 0) {
      p++;
    }
    return p;
  }
}

/// What the buyer sees on the checkout screen.
class FeeQuote {
  final double price;
  final double buyerFee;
  final double buyerFeeGst;
  final double deliveryFlat;
  final double deliveryBuyerShare;

  /// The seller's half of the fixed delivery fee.
  final double deliverySellerShare;

  /// What the seller would receive after commission, GST, delivery share
  /// and TDS. When this is <= 0 the order can never be placed — the item
  /// price doesn't cover the delivery split.
  final double sellerPayout;

  /// What the buyer pays — the Cashfree order_amount.
  final double buyerTotal;

  const FeeQuote({
    required this.price,
    required this.buyerFee,
    required this.buyerFeeGst,
    required this.deliveryFlat,
    required this.deliveryBuyerShare,
    required this.deliverySellerShare,
    required this.buyerTotal,
    required this.sellerPayout,
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
