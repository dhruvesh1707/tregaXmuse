/// Build / environment configuration for the Trega app.
///
/// The API base URL can be overridden at build time without code changes:
/// ```sh
/// flutter run --dart-define=TREGA_API_BASE_URL=https://api.trega.in/v1
/// ```
abstract final class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'TREGA_API_BASE_URL',
    defaultValue: 'https://api.trega.example.com/v1',
  );

  /// App name shown in UI chrome.
  static const String appName = 'Trega';

  /// Deep-link scheme reserved for Trega links (trega://listing/<id>).
  /// TODO: register scheme in AndroidManifest.xml / Info.plist.
  static const String deepLinkScheme = 'trega';
}
