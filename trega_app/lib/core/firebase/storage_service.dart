import 'dart:io';
import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Uploads media to Firebase Storage for Trega.
///
/// Paths (see `storage.rules`):
/// - `listingMedia/{listingId}/{timestamp}_{index}.jpg`, listing photos,
///   publicly readable once the listing is live.
/// - `avatars/{uid}.jpg`, user profile photos.
///
/// The legacy REST media upload in `core/api/` is DEPRECATED.
class StorageService {
  StorageService(this._storage);

  final FirebaseStorage _storage;

  /// Uploads listing photos and returns their download URLs, in order.
  ///
  /// Photos upload in parallel, 3 at a time: the uploads are
  /// independent, and uploading one by one made publish time the sum
  /// of every photo. Order is preserved, `Future.wait` keeps result
  /// order within each chunk and chunks run in order. Listing photos
  /// are immutable (timestamped names, never overwritten), so they
  /// carry a 1-year cache header and repeat loads skip the network.
  Future<List<String>> uploadListingImages(
      String listingId, List<XFile> images,) async {
    const maxConcurrent = 3;
    final urls = <String>[];
    for (var start = 0; start < images.length; start += maxConcurrent) {
      final end = min(start + maxConcurrent, images.length);
      final chunk = await Future.wait([
        for (var i = start; i < end; i++)
          _uploadOneListingImage(listingId, images[i], i),
      ]);
      urls.addAll(chunk);
    }
    return urls;
  }

  /// Uploads one listing photo and returns its download URL.
  Future<String> _uploadOneListingImage(
      String listingId, XFile image, int index,) async {
    final file = File(image.path);
    final ref = _storage.ref().child(
        'listingMedia/$listingId/${DateTime.now().millisecondsSinceEpoch}_$index.jpg',);
    await ref.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      ),
    );
    return ref.getDownloadURL();
  }

  /// Uploads a user avatar and returns its download URL.
  Future<String> uploadAvatar(String uid, XFile image) async {
    final file = File(image.path);
    final ref = _storage.ref().child('avatars/$uid.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
