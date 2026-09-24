/// A seller's saved pickup address, stored owner-only under
/// `users/{uid}/private/address_<id>` (see `firestore.rules`).
/// Never shown to buyers — reused across listings in the sell flow.
class SavedAddress {
  final String id;
  final String label;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final DateTime createdAt;

  const SavedAddress({
    required this.id,
    this.label = '',
    required this.line1,
    this.line2 = '',
    required this.city,
    required this.state,
    required this.pincode,
    required this.createdAt,
  });

  String get displayLabel =>
      label.isNotEmpty ? label : '$city $pincode';

  String get fullAddress {
    final parts = <String>[
      line1,
      if (line2.isNotEmpty) line2,
      '$city, $state $pincode',
    ];
    return parts.join(', ');
  }

  Map<String, dynamic> toMap() => {
        'kind': 'address',
        'label': label,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedAddress.fromFirestore(String id, Map<String, dynamic> data) {
    return SavedAddress(
      id: id,
      label: data['label'] as String? ?? '',
      line1: data['line1'] as String? ?? '',
      line2: data['line2'] as String? ?? '',
      city: data['city'] as String? ?? '',
      state: data['state'] as String? ?? '',
      pincode: data['pincode'] as String? ?? '',
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Same physical address? Used to dedupe auto-saved addresses.
  bool sameAs(SavedAddress other) =>
      line1.trim().toLowerCase() == other.line1.trim().toLowerCase() &&
      city.trim().toLowerCase() == other.city.trim().toLowerCase() &&
      state.trim().toLowerCase() == other.state.trim().toLowerCase() &&
      pincode.trim() == other.pincode.trim();
}
