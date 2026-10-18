import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/auth_di.dart';
import '../../models/trip_model.dart';

class TripRepository {
  final Dio _dio;

  TripRepository({required Dio dio}) : _dio = dio;

  void _log(String event, [Map<String, dynamic>? data]) {
    final payload = data != null ? '$event: $data' : event;
    developer.log('[TripRepository] $payload', name: 'TripRepository');
  }

  /// Get all trips for the authenticated user from SQL Server.
  Future<List<Trip>> getTrips() async {
    try {
      _log('getTrips_request');
      final response = await _dio.get('/api/v1/trips');
      if (response.statusCode == 200 && response.data is List) {
        final list = (response.data as List)
            .map((item) => Trip.fromJson(item as Map<String, dynamic>))
            .toList();
        _log('getTrips_success', {'count': list.length});
        return list;
      }
      return [];
    } on DioException catch (e) {
      _log('getTrips_error', {'error': e.message, 'statusCode': e.response?.statusCode});
      return [];
    } catch (e) {
      _log('getTrips_unexpected_error', {'error': e.toString()});
      return [];
    }
  }

  /// Get the full itinerary with days, activities, and places for a trip.
  Future<Trip?> getTripItinerary(String tripId) async {
    try {
      _log('getTripItinerary_request', {'tripId': tripId});
      final response = await _dio.get('/api/v1/trips/$tripId/itinerary');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final trip = Trip.fromJson(response.data as Map<String, dynamic>);
        _log('getTripItinerary_success', {'tripId': tripId, 'days': trip.days.length});
        return trip;
      }
      return null;
    } on DioException catch (e) {
      _log('getTripItinerary_error', {'tripId': tripId, 'error': e.message});
      return null;
    } catch (e) {
      _log('getTripItinerary_unexpected_error', {'error': e.toString()});
      return null;
    }
  }

  /// Generate a preview itinerary from planning context without saving to DB.
  Future<Trip> generateItineraryPreview({required int conversationId}) async {
    _log('generateItineraryPreview_request', {'conversationId': conversationId});
    try {
      final response = await _dio.post(
        '/api/v1/trips/generate',
        data: {
          'conversation_id': conversationId,
          'save_to_db': false,
        },
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final trip = Trip.fromJson(response.data as Map<String, dynamic>);
        _log('generateItineraryPreview_success', {
          'title': trip.title,
          'days': trip.days.length,
          'stops': trip.totalStops,
        });
        return trip;
      }
      throw Exception('Lỗi từ máy chủ khi tạo lịch trình (${response.statusCode})');
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? e.message;
      _log('generateItineraryPreview_dio_error', {'detail': detail});
      throw Exception('Không thể tạo lịch trình: $detail');
    }
  }

  /// Persist the reviewed preview into SQL Server atomically and idempotently.
  Future<String> saveTripPreview({
    required Trip trip,
    required int conversationId,
    String? idempotencyKey,
  }) async {
    _log('saveTripPreview_request', {
      'conversationId': conversationId,
      'tripTitle': trip.title,
    });
    try {
      final key = idempotencyKey ??
          'save_${conversationId}_${trip.title.hashCode}_${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
      
      final payload = {
        'conversation_id': conversationId,
        'preview': trip.rawJson ?? trip.toJson(),
        'idempotency_key': key,
      };

      final response = await _dio.post('/api/v1/trips/save-preview', data: payload);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data is Map<String, dynamic>) {
        final tripId = response.data['trip_id']?.toString() ?? '';
        _log('saveTripPreview_success', {'tripId': tripId});
        return tripId;
      }
      throw Exception('Lỗi máy chủ khi lưu chuyến đi (${response.statusCode})');
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? e.message;
      _log('saveTripPreview_error', {'detail': detail});
      throw Exception('Không thể lưu chuyến đi: $detail');
    }
  }

  /// Edit an existing trip itinerary with voice or text instruction.
  Future<Trip?> editItinerary({
    required String tripId,
    required String instruction,
  }) async {
    _log('editItinerary_request', {'tripId': tripId, 'instruction': instruction});
    try {
      final response = await _dio.post(
        '/api/v1/trips/$tripId/itinerary/edit',
        data: {'instruction': instruction},
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final updatedTrip = Trip.fromJson(response.data as Map<String, dynamic>);
        _log('editItinerary_success', {'tripId': tripId});
        return updatedTrip;
      }
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? e.message;
      _log('editItinerary_error', {'detail': detail});
      throw Exception('Không thể chỉnh sửa lịch trình: $detail');
    }
  }
}

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final dio = ref.watch(dioClientProvider).dio;
  return TripRepository(dio: dio);
});
