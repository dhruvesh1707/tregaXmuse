import 'package:dio/dio.dart';

/// Central HTTP client for all Trega backend calls.
///
/// Usage:
/// ```dart
/// ApiClient.instance.init(baseUrl: AppConfig.baseUrl); // once, in main()
/// final dio = ApiClient.instance.dio;
/// ```
///
/// TODO(backend):
///   - Implement token refresh on 401 (call POST /auth/refresh, retry once).
///   - Persist tokens in flutter_secure_storage; hydrate via [setAuthToken].
///   - Add request logging only for debug builds.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  String? _authToken;
  bool _initialized = false;

  /// Must be called once before any request (see [main]).
  void init({required String baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-App-Platform': 'flutter',
        },
      ),
    );

    // Auth interceptor: attaches the bearer token to every request.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _authToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // TODO(backend): if error.response?.statusCode == 401 -> refresh
          // token, update via setAuthToken, and retry the original request.
          handler.next(error);
        },
      ),
    );

    _initialized = true;
  }

  /// Updates the bearer token used by the auth interceptor.
  /// Pass null on logout.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  Dio get dio {
    assert(_initialized, 'ApiClient.init() must be called before use.');
    return _dio;
  }
}
