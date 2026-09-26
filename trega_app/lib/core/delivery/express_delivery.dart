import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_providers.dart';

/// Trega Express — next-day delivery within the same city.
///
/// This is the marketing name users see. The courier partners behind it are
/// never named anywhere in the app; copy only ever says "Trega Express".
///
/// Eligibility is intentionally conservative: a listing only earns the
/// Express badge when its [Listing.city] is in [cities], and an order only
/// counts as express when the buyer's delivery city matches the listing's
/// city. The city list and cutoff hour ship as bundled defaults and can be
/// overridden remotely via the `config/delivery` Firestore doc (public read,
/// console-only write) — no app release needed to add a city.
class ExpressDeliveryConfig {
  final bool enabled;
  final List<String> cities;
  final int cutoffHour;

  const ExpressDeliveryConfig({
    required this.enabled,
    required this.cities,
    required this.cutoffHour,
  });

  /// Bundled defaults — used until (and unless) `config/delivery` exists.
  /// City names are stored normalized (lowercase, trimmed).
  static const ExpressDeliveryConfig defaults = ExpressDeliveryConfig(
    enabled: true,
    cities: <String>[
      'mumbai',
      'delhi',
      'new delhi',
      'bengaluru',
      'bangalore',
      'hyderabad',
      'chennai',
      'pune',
      'kolkata',
      'ahmedabad',
    ],
    cutoffHour: 21,
  );

  factory ExpressDeliveryConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    final rawCities = map['expressCities'];
    return ExpressDeliveryConfig(
      enabled: map['enabled'] as bool? ?? defaults.enabled,
      cities: rawCities is List
          ? rawCities.whereType<String>().map(normalizeCity).toList()
          : defaults.cities,
      cutoffHour: (map['cutoffHour'] as num?)?.toInt() ?? defaults.cutoffHour,
    );
  }

  /// Normalizes a city for comparison: " Mumbai " → "mumbai".
  static String normalizeCity(String city) => city.trim().toLowerCase();

  /// Is this city served by Trega Express at all?
  bool isCityEligible(String city) =>
      enabled &&
      city.trim().isNotEmpty &&
      cities.contains(normalizeCity(city));

  /// Full order eligibility: same eligible city on both ends.
  bool isOrderEligible({
    required String listingCity,
    required String buyerCity,
  }) =>
      isCityEligible(listingCity) &&
      normalizeCity(listingCity) == normalizeCity(buyerCity);

  /// Days until delivery for an order placed at [now]: 1 when placed before
  /// today's cutoff, 2 after it.
  int daysUntilDelivery(DateTime now) {
    final cutoff = DateTime(now.year, now.month, now.day, cutoffHour);
    return now.isBefore(cutoff) ? 1 : 2;
  }

  /// Human label for the delivery day: "tomorrow" / "day after tomorrow".
  String deliveryDayLabel(DateTime now) =>
      daysUntilDelivery(now) == 1 ? 'tomorrow' : 'day after tomorrow';

  /// Time left until today's cutoff (only meaningful when
  /// [daysUntilDelivery] is 1). Rendered as "2h 14m".
  String cutoffCountdownLabel(DateTime now) {
    final cutoff = DateTime(now.year, now.month, now.day, cutoffHour);
    var remaining = cutoff.difference(now);
    if (remaining.isNegative) remaining = Duration.zero;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}

/// Live Trega Express config: the `config/delivery` doc over bundled
/// defaults, so the team can add cities from the Firebase console.
final expressConfigProvider = StreamProvider<ExpressDeliveryConfig>(
  (ref) => ref
      .watch(firestoreServiceProvider)
      .watchDeliveryConfig()
      .map(ExpressDeliveryConfig.fromMap),
);
