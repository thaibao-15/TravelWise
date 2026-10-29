import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/home/data/home_remote_data_source.dart';

void main() {
  test(
    'getNearbyPlaces calls nearby endpoint and parses returned distance',
    () async {
      RequestOptions? capturedRequest;
      final dio = Dio(BaseOptions(baseUrl: 'https://travelwise.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: [
                  {
                    'id': 42,
                    'name': 'Cầu Rồng',
                    'description': 'Cầu bắc qua sông Hàn',
                    'latitude': 16.061,
                    'longitude': 108.227,
                    'rating_avg': 4.8,
                    'review_count': 23,
                    'distance_km': 1.25,
                    'images': [
                      {'url': '/uploads/dragon-bridge.jpg'},
                    ],
                  },
                ],
              ),
            );
          },
        ),
      );

      final places = await HomeRemoteDataSource(dio).getNearbyPlaces(
        latitude: 16.06,
        longitude: 108.22,
        radiusKm: 5,
        limit: 10,
      );

      expect(capturedRequest?.path, '/api/v1/places/nearby');
      expect(capturedRequest?.queryParameters, {
        'latitude': 16.06,
        'longitude': 108.22,
        'radius_km': 5,
        'limit': 10,
      });
      expect(places, hasLength(1));
      expect(places.single.distanceKm, 1.25);
      expect(
        places.single.imageUrl,
        'https://travelwise.test/uploads/dragon-bridge.jpg',
      );
    },
  );
}
