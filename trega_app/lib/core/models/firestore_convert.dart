import 'package:cloud_firestore/cloud_firestore.dart';

/// Helpers to bridge Firestore field types and Dart models.
///
/// Firestore stores dates as [Timestamp]; legacy JSON used ISO-8601 strings.
/// These helpers accept both so `fromFirestore` also tolerates imported data.
DateTime firestoreDate(dynamic value, {DateTime? fallback}) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback ?? DateTime.now();
}

/// Always write dates as Firestore [Timestamp]s.
Timestamp firestoreTimestamp(DateTime dateTime) =>
    Timestamp.fromDate(dateTime);

List<String> firestoreStringList(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  return const [];
}

Map<String, String> firestoreStringMap(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  return const {};
}
