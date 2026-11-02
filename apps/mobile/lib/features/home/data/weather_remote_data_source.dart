import 'package:dio/dio.dart';

import '../models/weather_model.dart';

class WeatherRemoteDataSource {
  final Dio _dio;

  const WeatherRemoteDataSource(this._dio);

  Future<WeatherResponse> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _dio.get(
      '/api/v1/weather',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'forecast_days': 1,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw const FormatException('API trả về dữ liệu thời tiết không hợp lệ');
    }

    return WeatherResponse.fromJson(Map<String, dynamic>.from(data));
  }
}
