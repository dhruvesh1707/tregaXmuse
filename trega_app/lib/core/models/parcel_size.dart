/// Packed parcel size for courier shipping, captured after the sale.
///
/// The seller prompt on the order tracking view prefills these values
/// from the category table below and the seller can adjust them. The shipment backend
/// (`trega_functions/src/shiprocket.ts`, `freightFor`) uses the order's
/// own parcel fields when present, then the listing's, and falls back to
/// its `FREIGHT_DEFAULTS` table otherwise, so keep the two tables in sync:
/// same per-category values, same caps.
class ParcelSize {
  /// Packed weight in kilograms.
  final double weightKg;

  /// Box dimensions in centimeters.
  final double lengthCm;
  final double breadthCm;
  final double heightCm;

  const ParcelSize({
    required this.weightKg,
    required this.lengthCm,
    required this.breadthCm,
    required this.heightCm,
  });
}

/// Category parcel defaults and validation caps, mirroring the backend
/// `FREIGHT_DEFAULTS` table. Keys are the canonical category ids.
class ParcelDefaults {
  /// Weight must be within 0.1 to 50 kg.
  static const double minWeightKg = 0.1;
  static const double maxWeightKg = 50;

  /// Each box dimension must be within 1 to 200 cm.
  static const double minDimensionCm = 1;
  static const double maxDimensionCm = 200;

  static const Map<String, ParcelSize> byCategory = {
    'gaming': ParcelSize(
        weightKg: 2, lengthCm: 35, breadthCm: 28, heightCm: 12,),
    'mobiles': ParcelSize(
        weightKg: 0.5, lengthCm: 20, breadthCm: 12, heightCm: 8,),
    'laptops': ParcelSize(
        weightKg: 2.5, lengthCm: 45, breadthCm: 32, heightCm: 8,),
    'cameras': ParcelSize(
        weightKg: 1.5, lengthCm: 30, breadthCm: 22, heightCm: 15,),
    'music': ParcelSize(
        weightKg: 3, lengthCm: 40, breadthCm: 30, heightCm: 15,),
    'fashion': ParcelSize(
        weightKg: 0.5, lengthCm: 30, breadthCm: 22, heightCm: 5,),
    'furniture': ParcelSize(
        weightKg: 10, lengthCm: 60, breadthCm: 50, heightCm: 40,),
    'appliances': ParcelSize(
        weightKg: 8, lengthCm: 55, breadthCm: 45, heightCm: 40,),
    'cycles': ParcelSize(
        weightKg: 12, lengthCm: 120, breadthCm: 25, heightCm: 70,),
    'watches': ParcelSize(
        weightKg: 0.5, lengthCm: 18, breadthCm: 12, heightCm: 8,),
    'collectibles': ParcelSize(
        weightKg: 1, lengthCm: 30, breadthCm: 22, heightCm: 12,),
    'books': ParcelSize(
        weightKg: 1, lengthCm: 30, breadthCm: 22, heightCm: 8,),
    'others': ParcelSize(
        weightKg: 1, lengthCm: 30, breadthCm: 22, heightCm: 12,),
  };

  /// Default parcel for a category id, `others` for unknown ids.
  static ParcelSize forCategory(String? categoryId) =>
      byCategory[categoryId] ?? byCategory['others']!;

  /// Formats a parcel number without a trailing `.0` (20, not 20.0),
  /// so prefilled fields read like typed values.
  static String formatNumber(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
