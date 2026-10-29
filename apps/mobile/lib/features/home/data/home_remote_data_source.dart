import 'package:dio/dio.dart';

import '../models/category_model.dart';
import '../models/place_model.dart';

class HomeRemoteDataSource {
  final Dio _dio;

  const HomeRemoteDataSource(this._dio);

  Future<List<Category>> getCategories() async {
    final response = await _dio.get('/api/v1/categories/');
    return _parseList(
      response.data,
    ).map(Category.fromJson).toList(growable: false);
  }

  Future<List<Place>> getPlaces({int? categoryId}) async {
    final response = await _dio.get(
      '/api/v1/places/',
      queryParameters: {'category_id': ?categoryId, 'skip': 0, 'limit': 50},
    );

    return _parseList(response.data)
        .map((json) => Place.fromJson(json, imageBaseUrl: _dio.options.baseUrl))
        .toList(growable: false);
  }

  Future<List<Place>> getNearbyPlaces({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
    int limit = 20,
  }) async {
    final response = await _dio.get(
      '/api/v1/places/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
        'limit': limit,
      },
    );

    return _parseList(response.data)
        .map((json) => Place.fromJson(json, imageBaseUrl: _dio.options.baseUrl))
        .toList(growable: false);
  }

  Future<List<Place>> getAllPlaces({int? categoryId}) async {
    const pageSize = 200;
    final places = <Place>[];
    var skip = 0;

    while (true) {
      final response = await _dio.get(
        '/api/v1/places/',
        queryParameters: {
          'category_id': ?categoryId,
          'skip': skip,
          'limit': pageSize,
        },
      );
      final page = _parseList(response.data)
          .map(
            (json) => Place.fromJson(json, imageBaseUrl: _dio.options.baseUrl),
          )
          .toList(growable: false);
      places.addAll(page);

      if (page.length < pageSize) {
        return places;
      }
      skip += pageSize;
    }
  }

  Future<List<Place>> searchPlaces(String query) async {
    final response = await _dio.get(
      '/api/v1/places/search',
      queryParameters: {'q': query, 'skip': 0, 'limit': 30},
    );

    return _parseList(response.data)
        .map((json) => Place.fromJson(json, imageBaseUrl: _dio.options.baseUrl))
        .toList(growable: false);
  }

  Future<Place> getPlaceById(int placeId) async {
    final response = await _dio.get('/api/v1/places/$placeId');
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('API trả về dữ liệu địa điểm không hợp lệ');
    }

    return Place.fromJson(
      Map<String, dynamic>.from(data),
      imageBaseUrl: _dio.options.baseUrl,
    );
  }

  List<Map<String, dynamic>> _parseList(dynamic data) {
    if (data is! List) {
      throw const FormatException('API trả về dữ liệu không hợp lệ');
    }

    return data
        .map((item) {
          if (item is! Map) {
            throw const FormatException('API trả về phần tử không hợp lệ');
          }
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }
}
