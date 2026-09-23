import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_convert.dart';

/// A Trega user (buyer and/or seller).
class AppUser {
  final String id;
  final String name;
  final String phone;
  final String? avatarUrl;
  final bool isVerifiedSeller;
  final double rating;
  final int reviewsCount;
  final DateTime? joinedAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.avatarUrl,
    this.isVerifiedSeller = false,
    this.rating = 0,
    this.reviewsCount = 0,
    this.joinedAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      isVerifiedSeller: json['is_verified_seller'] as bool? ?? false,
      rating: (json['rating'] as num? ?? 0).toDouble(),
      reviewsCount: json['reviews_count'] as int? ?? 0,
      joinedAt: json['joined_at'] == null
          ? null
          : DateTime.tryParse(json['joined_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'avatar_url': avatarUrl,
      'is_verified_seller': isVerifiedSeller,
      'rating': rating,
      'reviews_count': reviewsCount,
      'joined_at': joinedAt?.toIso8601String(),
    };
  }
}

/// Firestore serialization for `users/{uid}` documents.
///
/// Canonical fields (`trega_functions/FIRESTORE_MODEL.md`): `phone`, `name`,
/// `avatarUrl`, `role` (`buyer`|`seller`|`admin`), `verifiedSeller`,
/// `kycStatus` (`unverified`|`pending`|`verified`|`rejected`), `kycName?`,
/// `kycDob?`, `createdAt`.
///
/// Clients may only write their own doc on creation; `role`,
/// `verifiedSeller` and `kycStatus` are managed server-side (see
/// firestore.rules).
extension AppUserFirestore on AppUser {
  static AppUser fromFirestore(Map<String, dynamic> data, String uid) {
    return AppUser(
      id: uid,
      name: data['name'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      isVerifiedSeller: data['verifiedSeller'] as bool? ?? false,
      joinedAt: data['createdAt'] == null
          ? null
          : firestoreDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'phone': phone,
      'name': name,
      'avatarUrl': avatarUrl,
      'role': 'buyer',
      'verifiedSeller': isVerifiedSeller,
      'kycStatus': 'unverified',
      'createdAt': joinedAt == null
          ? FieldValue.serverTimestamp()
          : firestoreTimestamp(joinedAt!),
    };
  }
}
