import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

/// API configuration constants.
/// Switch [baseUrl] based on runtime target (emulator vs real device).
class ApiConfig {
  // Android Emulator maps 10.0.2.2 to the host machine.
  // For a physical device, replace this with the host machine's LAN IP.
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static const Duration connectTimeout = Duration(seconds: 60);
  static const Duration receiveTimeout = Duration(seconds: 120);
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
    if (kDebugMode) {
      _dio.interceptors.add(_loggingInterceptor());
    }
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

  /// Logging interceptor for debug builds (skips body buffering on streams/bytes).
  Interceptor _loggingInterceptor() {
    final baseLogger = LogInterceptor(
      request: true,
      requestHeader: false,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    );
    return InterceptorsWrapper(
      onRequest: baseLogger.onRequest,
      onResponse: (response, handler) {
        final rt = response.requestOptions.responseType;
        if (rt == ResponseType.stream || rt == ResponseType.bytes) {
          return handler.next(response);
        }
        return baseLogger.onResponse(response, handler);
      },
      onError: baseLogger.onError,
    );
  }
}
