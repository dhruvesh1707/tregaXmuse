/// Build-time observability configuration.
///
/// All values are injected with `--dart-define` at build time. An empty
/// value means that integration is disabled and the app runs exactly as
/// before — so debug builds and builds without keys behave identically to
/// today. Nothing observability-related is hardcoded or committed.
///
/// Android release example:
///   flutter build appbundle --release
///     --dart-define=SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
///     --dart-define=DD_CLIENT_TOKEN=xxx
///     --dart-define=DD_APPLICATION_ID=xxx
///
/// iOS: the same flags are passed by the `iOS unsigned IPA` GitHub workflow
/// from repository secrets (SENTRY_DSN, DD_CLIENT_TOKEN, DD_APPLICATION_ID,
/// DD_SITE).
class ObservabilityConfig {
  ObservabilityConfig._();

  /// Sentry DSN, e.g. https://<key>@<org>.ingest.sentry.io/<project>.
  /// From sentry.io → your project → Settings → Client Keys.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Datadog RUM client token.
  /// From Datadog → RUM → New Application → Client Token.
  static const datadogClientToken =
      String.fromEnvironment('DD_CLIENT_TOKEN');

  /// Datadog RUM application ID (same screen as the client token).
  static const datadogApplicationId =
      String.fromEnvironment('DD_APPLICATION_ID');

  /// Datadog site: us1 | us3 | us5 | eu1 | ap1 | ap2.
  /// Must match the site your Datadog org lives on.
  static const datadogSite =
      String.fromEnvironment('DD_SITE', defaultValue: 'us1');

  /// Datadog environment tag, e.g. production / staging.
  static const datadogEnv =
      String.fromEnvironment('DD_ENV', defaultValue: 'production');

  static bool get sentryEnabled => sentryDsn.isNotEmpty;

  static bool get datadogEnabled =>
      datadogClientToken.isNotEmpty && datadogApplicationId.isNotEmpty;
}
