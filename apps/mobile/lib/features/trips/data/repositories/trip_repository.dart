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

  /// Get all trips for the authenticated user from SQL Server (`GET /api/v1/trips`).
  /// Supports both paginated `{total, skip, limit, items: [...]}` and raw list responses.
  Future<List<Trip>> getTrips({
    int skip = 0,
    int limit = 50,
    String? status,
  }) async {
    try {
      _log('getTrips_request', {'skip': skip, 'limit': limit, 'status': status});
      final queryParams = <String, dynamic>{
        'skip': skip,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
      };
      final response = await _dio.get(
        '/api/v1/trips',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        List<dynamic> rawItems = [];
        if (response.data is Map<String, dynamic>) {
          final map = response.data as Map<String, dynamic>;
          if (map['items'] is List) {
            rawItems = map['items'] as List<dynamic>;
          } else if (map['data'] is List) {
            rawItems = map['data'] as List<dynamic>;
          }
        } else if (response.data is List) {
          rawItems = response.data as List<dynamic>;
        }

        final list = rawItems
            .whereType<Map<String, dynamic>>()
            .map((item) => Trip.fromJson(item))
            .toList();
        _log('getTrips_success', {'count': list.length});
        return list;
      }
      return [];
    } on DioException catch (e) {
      _log('getTrips_error', {
        'error': e.message,
        'statusCode': e.response?.statusCode,
      });
      return [];
    } catch (e) {
      _log('getTrips_unexpected_error', {'error': e.toString()});
      return [];
    }
  }

  /// Get single trip overview metadata (`GET /api/v1/trips/{tripId}`).
  Future<Trip?> getTripById(String tripId) async {
    try {
      _log('getTripById_request', {'tripId': tripId});
      final response = await _dio.get('/api/v1/trips/$tripId');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final trip = Trip.fromJson(response.data as Map<String, dynamic>);
        _log('getTripById_success', {'tripId': tripId, 'title': trip.title});
        return trip;
      }
      return null;
    } on DioException catch (e) {
      _log('getTripById_error', {
        'tripId': tripId,
        'error': e.message,
        'statusCode': e.response?.statusCode,
      });
      return null;
    } catch (e) {
      _log('getTripById_unexpected_error', {'error': e.toString()});
      return null;
    }
  }

  /// Get the full itinerary with days, activities, and places for a trip
  /// (`GET /api/v1/trips/{tripId}/itinerary` with fallback/merge from `GET /api/v1/trips/{tripId}`).
  Future<Trip?> getTripItinerary(String tripId) async {
    try {
      _log('getTripItinerary_request', {'tripId': tripId});
      final results = await Future.wait([
        _dio.get('/api/v1/trips/$tripId/itinerary').catchError((_) => Response(
              requestOptions: RequestOptions(path: '/api/v1/trips/$tripId/itinerary'),
              statusCode: 404,
            )),
        _dio.get('/api/v1/trips/$tripId').catchError((_) => Response(
              requestOptions: RequestOptions(path: '/api/v1/trips/$tripId'),
              statusCode: 404,
            )),
      ]);

      final itineraryRes = results[0];
      final summaryRes = results[1];

      Map<String, dynamic>? mergedJson;
      if (summaryRes.statusCode == 200 && summaryRes.data is Map<String, dynamic>) {
        mergedJson = Map<String, dynamic>.from(summaryRes.data as Map<String, dynamic>);
      }
      if (itineraryRes.statusCode == 200 && itineraryRes.data is Map<String, dynamic>) {
        final itinMap = itineraryRes.data as Map<String, dynamic>;
        if (mergedJson != null) {
          mergedJson.addAll(itinMap);
        } else {
          mergedJson = Map<String, dynamic>.from(itinMap);
        }
      }

      if (mergedJson != null) {
        final trip = Trip.fromJson(mergedJson);
        _log('getTripItinerary_success', {
          'tripId': tripId,
          'days': trip.days.length,
          'stops': trip.totalStops,
        });
        return trip;
      }
      return null;
    } on DioException catch (e) {
      _log('getTripItinerary_error', {'tripId': tripId, 'error': e.message});
      return await getTripById(tripId);
    } catch (e) {
      _log('getTripItinerary_unexpected_error', {'error': e.toString()});
      return null;
    }
  }

  /// Create a new trip in SQL Server (`POST /api/v1/trips`).
  Future<Trip?> createTrip({
    required String destinationCity,
    String? name,
    String destinationCountry = 'Việt Nam',
    String? startDate,
    String? endDate,
    int durationDays = 3,
  }) async {
    try {
      _log('createTrip_request', {'destinationCity': destinationCity, 'name': name});
      final response = await _dio.post(
        '/api/v1/trips',
        data: {
          'name': name ?? 'Chuyến đi $destinationCity',
          'destination_city': destinationCity,
          'destination_country': destinationCountry,
          if (startDate != null) 'start_date': startDate,
          if (endDate != null) 'end_date': endDate,
          'duration_days': durationDays,
        },
      );
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data is Map<String, dynamic>) {
        return Trip.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? e.message;
      _log('createTrip_error', {'detail': detail});
      throw Exception('Không thể tạo chuyến đi: $detail');
    }
  }

  /// Delete a trip (`DELETE /api/v1/trips/{tripId}`).
  Future<bool> deleteTrip(String tripId) async {
    try {
      _log('deleteTrip_request', {'tripId': tripId});
      final response = await _dio.delete('/api/v1/trips/$tripId');
      return response.statusCode == 204 || response.statusCode == 200;
    } on DioException catch (e) {
      _log('deleteTrip_error', {'tripId': tripId, 'error': e.message});
      return false;
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

  /// Generate or regenerate itinerary for an existing trip (`POST /api/v1/trips/{tripId}/itinerary/generate`).
  Future<Trip?> generateItineraryForTrip(
    String tripId, {
    String? userPrompt,
    bool saveToDb = true,
  }) async {
    try {
      _log('generateItineraryForTrip_request', {'tripId': tripId});
      final response = await _dio.post(
        '/api/v1/trips/$tripId/itinerary/generate',
        data: {
          'save_to_db': saveToDb,
          if (userPrompt != null && userPrompt.isNotEmpty) 'user_prompt': userPrompt,
        },
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return await getTripItinerary(tripId) ??
            Trip.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? e.message;
      _log('generateItineraryForTrip_error', {'detail': detail});
      throw Exception('Không thể tạo lịch trình cho chuyến đi: $detail');
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
        'name': trip.title,
        'destination_city': trip.destination.split(',').first.trim(),
        'preview': trip.rawJson ?? trip.toJson(),
        'idempotency_key': key,
      };

      final response = await _dio.post('/api/v1/trips/save-preview', data: payload);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final tripId = (data['trip_id'] ?? data['id'] ?? '').toString();
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

  /// Edit an existing trip itinerary with voice or text instruction (`POST /api/v1/trips/{tripId}/itinerary/edit`).
  Future<Trip?> editItinerary({
    required String tripId,
    required String instruction,
  }) async {
    _log('editItinerary_request', {'tripId': tripId, 'instruction': instruction});
    try {
      final response = await _dio.post(
        '/api/v1/trips/$tripId/itinerary/edit',
        data: {
          'change_prompt': instruction,
          'instruction': instruction,
        },
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        final itineraryData = map['itinerary'] is Map<String, dynamic>
            ? map['itinerary'] as Map<String, dynamic>
            : map;
        final updatedTrip = Trip.fromJson(itineraryData);
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
