import 'package:dio/dio.dart';

import '../models/category_model.dart';
import '../models/place_model.dart';

class HomeRemoteDataSource {
  final Dio _dio;

  const HomeRemoteDataSource(this._dio);

  Future<List<Category>> getCategories() async {
    final response = await _dio.get('/api/v1/categories/');
    return _parseList(response.data)
        .map(Category.fromJson)
        .toList(growable: false);
  }

  Future<List<Place>> getPlaces({int? categoryId}) async {
    final response = await _dio.get(
      '/api/v1/places/',
      queryParameters: {
        if (categoryId != null) 'category_id': categoryId,
        'skip': 0,
        'limit': 50,
      },
    );

    return _parseList(response.data)
        .map(
          (json) => Place.fromJson(
            json,
            imageBaseUrl: _dio.options.baseUrl,
          ),
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _parseList(dynamic data) {
    if (data is! List) {
      throw const FormatException('API trả về dữ liệu không hợp lệ');
    }

    return data.map((item) {
      if (item is! Map) {
        throw const FormatException('API trả về phần tử không hợp lệ');
      }
      return Map<String, dynamic>.from(item);
    }).toList(growable: false);
  }
}
