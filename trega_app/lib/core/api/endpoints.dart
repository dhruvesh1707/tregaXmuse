/// REST endpoint catalogue for the Trega backend.
///
/// All paths are relative to [AppConfig.baseUrl]. Keep in sync with the
/// backend OpenAPI spec (see backend repo `/docs/openapi.yaml`).
abstract final class ApiEndpoints {
  // Auth
  static const String sendOtp = '/auth/otp/send';
  static const String verifyOtp = '/auth/otp/verify';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';

  // Users
  static const String me = '/users/me';
  static const String updateProfile = '/users/me';

  // Catalogue
  static const String categories = '/categories';

  // Listings
  static const String listings = '/listings';
  static String listing(String id) => '/listings/$id';
  static String listingBids(String id) => '/listings/$id/bids';
  static const String createListing = '/listings';
  static String updateListing(String id) => '/listings/$id';
  static const String uploadMedia = '/media/upload';

  // Bids & offers
  static const String bids = '/bids';
  static String bid(String id) => '/bids/$id';
  static String acceptBid(String id) => '/bids/$id/accept';
  static String rejectBid(String id) => '/bids/$id/reject';

  // Orders & logistics
  static const String orders = '/orders';
  static String order(String id) => '/orders/$id';
  static String orderTracking(String id) => '/orders/$id/tracking';

  // Engagement
  static const String wishlist = '/wishlist';
  static String wishlistItem(String listingId) => '/wishlist/$listingId';
  static const String notifications = '/notifications';
  static String markNotificationRead(String id) =>
      '/notifications/$id/read';
}
