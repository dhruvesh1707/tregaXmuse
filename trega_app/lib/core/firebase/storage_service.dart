import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Uploads media to Firebase Storage for Trega.
///
/// Paths (see `storage.rules`):
/// - `listingMedia/{listingId}/{timestamp}_{index}.jpg` — listing photos,
///   publicly readable once the listing is live.
/// - `avatars/{uid}.jpg` — user profile photos.
///
/// The legacy REST media upload in `core/api/` is DEPRECATED.
class StorageService {
  StorageService(this._storage);

  final FirebaseStorage _storage;

  /// Uploads listing photos and returns their download URLs, in order.
  Future<List<String>> uploadListingImages(
      String listingId, List<XFile> images) async {
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      final file = File(images[i].path);
      final ref = _storage.ref().child(
          'listingMedia/$listingId/${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  /// Uploads a user avatar and returns its download URL.
  Future<String> uploadAvatar(String uid, XFile image) async {
    final file = File(image.path);
    final ref = _storage.ref().child('avatars/$uid.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
