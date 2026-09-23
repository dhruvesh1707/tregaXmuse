/// Condition grading used across Trega listings.
///
/// Wire values are the lowercase snake_case strings in Firestore
/// (`brand_new` …), matching the Cloud Functions data model.
enum Condition {
  brandNew,
  likeNew,
  good,
  fair,
}

extension ConditionLabel on Condition {
  String get label {
    switch (this) {
      case Condition.brandNew:
        return 'Brand New';
      case Condition.likeNew:
        return 'Like New';
      case Condition.good:
        return 'Good';
      case Condition.fair:
        return 'Fair';
    }
  }

  /// Firestore wire value, e.g. `like_new`.
  String get wireValue {
    switch (this) {
      case Condition.brandNew:
        return 'brand_new';
      case Condition.likeNew:
        return 'like_new';
      case Condition.good:
        return 'good';
      case Condition.fair:
        return 'fair';
    }
  }

  static Condition fromJson(String value) {
    return Condition.values.firstWhere(
      (c) => c.name == value,
      orElse: () => Condition.good,
    );
  }

  static Condition fromWire(String value) {
    return Condition.values.firstWhere(
      (c) => c.wireValue == value,
      orElse: () => Condition.good,
    );
  }
}

/// A product being sold on Trega: the item itself, independent of the sale.
class Product {
  final String id;
  final String title;
  final String description;
  final String categoryId;
  final Condition condition;
  final List<String> imageUrls;
  final String? videoUrl;
  final Map<String, String> specs;

  const Product({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.condition,
    required this.imageUrls,
    this.videoUrl,
    this.specs = const {},
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      categoryId: json['category_id'] as String,
      condition: ConditionLabel.fromJson(json['condition'] as String? ?? ''),
      imageUrls: (json['image_urls'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      videoUrl: json['video_url'] as String?,
      specs: (json['specs'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category_id': categoryId,
      'condition': condition.name,
      'image_urls': imageUrls,
      'video_url': videoUrl,
      'specs': specs,
    };
  }

  /// Placeholder used when an order's listing snapshot is missing
  /// (e.g. legacy data). Never shown in normal flows.
  static const Product empty = Product(
    id: '',
    title: 'Listing unavailable',
    description: '',
    categoryId: '',
    condition: Condition.good,
    imageUrls: [],
  );
}
