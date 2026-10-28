import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../models/review_model.dart';

class ReviewService {
  final Dio _dio;

  ReviewService({Dio? dio})
      : _dio = dio ??
            DioClient(storageService: SecureStorageService()).dio;

  /// Lấy danh sách đánh giá của địa điểm từ API
  /// GET /api/v1/places/{place_id}/reviews
  Future<PlaceReviewList> getPlaceReviews({
    required int placeId,
    int? rating,
    String? tripType,
    String sortBy = 'newest',
    int skip = 0,
    int limit = 20,
  }) async {
    final queryParams = <String, dynamic>{
      'skip': skip,
      'limit': limit,
      'sort_by': sortBy,
    };

    if (rating != null) {
      queryParams['rating'] = rating;
    }
    if (tripType != null && tripType.isNotEmpty) {
      queryParams['trip_type'] = tripType;
    }

    final response = await _dio.get(
      '/api/v1/places/$placeId/reviews',
      queryParameters: queryParams,
    );

    return PlaceReviewList.fromJson(response.data as Map<String, dynamic>);
  }

  /// Đăng bài đánh giá mới kèm danh sách ảnh
  /// POST /api/v1/places/{place_id}/reviews
  Future<PlaceReview> createReview({
    required int placeId,
    required int rating,
    String? title,
    String? comment,
    String? tripType,
    DateTime? visitedAt,
    List<String> imageUrls = const [],
  }) async {
    final imagesPayload = imageUrls
        .asMap()
        .entries
        .map(
          (e) => {
            'image_url': e.value,
            'caption': null,
            'display_order': e.key,
          },
        )
        .toList();

    final data = <String, dynamic>{
      'rating': rating,
      'title': title,
      'comment': comment,
      'trip_type': tripType,
      'visited_at': visitedAt?.toIso8601String().split('T').first,
      'images': imagesPayload,
    };

    final response = await _dio.post(
      '/api/v1/places/$placeId/reviews',
      data: data,
    );

    return PlaceReview.fromJson(response.data as Map<String, dynamic>);
  }

  /// Cập nhật bài đánh giá của người dùng hiện tại
  /// PUT /api/v1/reviews/{review_id}
  Future<PlaceReview> updateReview({
    required int reviewId,
    required int rating,
    String? title,
    String? comment,
    String? tripType,
    DateTime? visitedAt,
  }) async {
    final response = await _dio.put(
      '/api/v1/reviews/$reviewId',
      data: {
        'rating': rating,
        'title': title,
        'comment': comment,
        'trip_type': tripType,
        'visited_at': visitedAt?.toIso8601String().split('T').first,
      },
    );

    return PlaceReview.fromJson(response.data as Map<String, dynamic>);
  }

  /// Bấm thích hoặc bỏ thích đánh giá
  /// POST /api/v1/reviews/{review_id}/helpful
  Future<Map<String, dynamic>> toggleHelpfulVote({
    required int reviewId,
  }) async {
    final response = await _dio.post(
      '/api/v1/reviews/$reviewId/helpful',
    );
    return response.data as Map<String, dynamic>;
  }

  /// Xóa bài đánh giá
  /// DELETE /api/v1/reviews/{review_id}
  Future<void> deleteReview({required int reviewId}) async {
    await _dio.delete('/api/v1/reviews/$reviewId');
  }
}
