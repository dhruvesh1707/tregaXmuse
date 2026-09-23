import 'firestore_convert.dart';

/// An in-app notification in the user's inbox (`users/{uid}/notifications`).
///
/// Written server-side by Cloud Functions (bid accepted/rejected, order
/// status changes, listing review decisions, price drops). Clients only
/// ever flip `read` — see `firestore.rules`.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    this.createdAt,
  });

  static AppNotification fromFirestore(
      Map<String, dynamic> data, String docId,) {
    return AppNotification(
      id: docId,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'system',
      read: data['read'] as bool? ?? false,
      createdAt: data['createdAt'] == null
          ? null
          : firestoreDate(data['createdAt']),
    );
  }
}
