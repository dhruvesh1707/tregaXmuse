import 'package:flutter/material.dart';

/// Marketplace category ("Explore by Passion").
///
/// Canonical fields (`trega_functions/FIRESTORE_MODEL.md`): `name`, `slug`,
/// `icon` (string key), `active`, `sortOrder`. Firestore stores `icon` as a
/// string so new categories can be added from the admin panel without an app
/// release; [iconKeyToIconData] maps it to a Material icon here.
class Category {
  final String id;
  final String name;
  final String slug;
  final IconData icon;

  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.icon,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      icon: Icons.category_outlined,
    );
  }

  static Category fromFirestore(Map<String, dynamic> data, String docId) {
    return Category(
      id: docId,
      name: data['name'] as String? ?? '',
      slug: data['slug'] as String? ?? '',
      icon: iconKeyToIconData(data['icon'] as String?),
    );
  }

  /// Maps a stored icon key to a Material icon. Unknown keys fall back to a
  /// generic category icon so admin-added categories never crash the app.
  static IconData iconKeyToIconData(String? key) {
    switch (key) {
      case 'gaming':
        return Icons.sports_esports_outlined;
      case 'mobile':
        return Icons.smartphone_outlined;
      case 'laptop':
        return Icons.laptop_outlined;
      case 'camera':
        return Icons.photo_camera_outlined;
      case 'music':
        return Icons.music_note_outlined;
      case 'watch':
        return Icons.watch_outlined;
      case 'collectible':
        return Icons.collections_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}
