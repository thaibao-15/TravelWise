import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

/// API configuration constants.
/// Switch [baseUrl] based on runtime target (emulator vs real device).
class ApiConfig {
  // For Android emulator use 10.0.2.2, for real device use your machine IP
  static const String baseUrl = 'http://127.0.0.1:8000';
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}

/// Factory that creates a configured Dio instance with auth interceptor.
class DioClient {
  final SecureStorageService _storageService;
  late final Dio _dio;

  DioClient({required SecureStorageService storageService})
      : _storageService = storageService {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(_authInterceptor());
    _dio.interceptors.add(_loggingInterceptor());
  }

  Dio get dio => _dio;

  /// Interceptor that attaches the Authorization header to every request
  /// and handles 401 responses globally by clearing stored tokens.
  Interceptor _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storageService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Token expired or invalid — clear stored credentials
          await _storageService.clearAll();
        }
        return handler.next(error);
      },
    );
  }

  /// Logging interceptor for debug builds.
  Interceptor _loggingInterceptor() {
    return LogInterceptor(
      request: true,
      requestHeader: false,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    );
  }
}
