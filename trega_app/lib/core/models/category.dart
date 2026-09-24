import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Marketplace category ("Explore by Passion").
///
/// Canonical fields (`trega_functions/FIRESTORE_MODEL.md`): `name`, `slug`,
/// `icon` (string key), `active`, `sortOrder`. Firestore stores `icon` as a
/// string so new categories can be added from the admin panel without an app
/// release; [iconKeyToIconData] maps it to a Phosphor icon here.
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
      icon: PhosphorIconsRegular.squaresFour,
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

  /// Maps a stored icon key to a Phosphor icon. Unknown keys fall back to a
  /// generic category icon so admin-added categories never crash the app.
  static IconData iconKeyToIconData(String? key) {
    switch (key) {
      case 'gaming':
        return PhosphorIconsRegular.gameController;
      case 'mobile':
        return PhosphorIconsRegular.deviceMobile;
      case 'laptop':
        return PhosphorIconsRegular.laptop;
      case 'camera':
        return PhosphorIconsRegular.camera;
      case 'music':
        return PhosphorIconsRegular.musicNote;
      case 'watch':
        return PhosphorIconsRegular.watch;
      case 'collectible':
        return PhosphorIconsRegular.images;
      default:
        return PhosphorIconsRegular.squaresFour;
    }
  }
}
