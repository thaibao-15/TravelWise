import 'package:dio/dio.dart';

/// No-op on native (Android/iOS/Desktop) — the default IOHttpClientAdapter
/// already handles CORS-free HTTP correctly.
void configurePlatformAdapter(Dio dio) {
  // Nothing to configure on native platforms.
}

