import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/trips/data/repositories/trip_repository.dart';

void main() {
  test(
    'missing trip during generation is reported as TripNotFoundException',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://travelwise.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 404,
                  data: {'detail': 'Không tìm thấy chuyến đi với ID 39.'},
                ),
              ),
            );
          },
        ),
      );

      final repository = TripRepository(dio: dio);

      await expectLater(
        repository.generateItineraryForTrip('39'),
        throwsA(
          isA<TripNotFoundException>().having(
            (error) => error.message,
            'message',
            'Không tìm thấy chuyến đi với ID 39.',
          ),
        ),
      );
    },
  );
}
