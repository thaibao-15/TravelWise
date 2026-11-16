import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/data/models/user_model.dart';
import '../models/user_profile_model.dart';

/// Remote data source for user profile and backend interactions.
class ProfileRemoteDataSource {
  final Dio _dio;

  ProfileRemoteDataSource(this._dio);

  /// GET /api/v1/auth/me
  /// Fetches real authenticated user information.
  Future<UserModel> getCurrentUser() async {
    try {
      final response = await _dio.get('/api/v1/auth/me');
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// PATCH /api/v1/users/{userId}
  /// Partial update for full_name and avatar_url.
  Future<UserModel> updateUser({
    required int userId,
    String? fullName,
    String? avatarUrl,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (fullName != null) payload['full_name'] = fullName;
      if (avatarUrl != null) payload['avatar_url'] = avatarUrl;

      final response = await _dio.patch('/api/v1/users/$userId', data: payload);
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// DELETE /api/v1/users/{userId}
  /// Deletes user account.
  Future<void> deleteUser(int userId) async {
    try {
      await _dio.delete('/api/v1/users/$userId');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// GET /api/v1/users/me/profile
  /// Fetches the authenticated user's travel preferences & personal profile.
  /// Returns null if 404 (user has not created a travel profile record yet).
  Future<UserProfileModel?> getUserTravelProfile() async {
    try {
      final response = await _dio.get('/api/v1/users/me/profile');
      if (response.data is Map<String, dynamic>) {
        return UserProfileModel.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _handleDioError(e);
    }
  }

  /// PUT or POST /api/v1/users/me/profile
  /// Saves the user's travel profile, automatically creating it if not existing.
  Future<UserProfileModel> saveUserTravelProfile(UserProfileModel model) async {
    final payload = model.toJson();
    try {
      final response = await _dio.put('/api/v1/users/me/profile', data: payload);
      return UserProfileModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        try {
          final postResp = await _dio.post('/api/v1/users/me/profile', data: payload);
          return UserProfileModel.fromJson(postResp.data as Map<String, dynamic>);
        } on DioException catch (postErr) {
          throw _handleDioError(postErr);
        }
      }
      throw _handleDioError(e);
    }
  }

  /// POST /api/v1/media/upload
  /// Uploads avatar image file and returns the resolved media URL.
  Future<String> uploadAvatar(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final fileName = file.name.isNotEmpty ? file.name : 'avatar.jpg';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
        'media_type': 'image',
      });
      final response = await _dio.post('/api/v1/media/upload', data: formData);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        String rawUrl = data['url']?.toString() ?? '';
        if (rawUrl.isNotEmpty &&
            !rawUrl.startsWith('http://') &&
            !rawUrl.startsWith('https://')) {
          final base = ApiConfig.baseUrl.endsWith('/')
              ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
              : ApiConfig.baseUrl;
          final path = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
          rawUrl = '$base$path';
        }
        return rawUrl;
      } else {
        throw ServerException(message: 'Tải ảnh lên máy chủ thất bại');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(message: 'Lỗi tải ảnh đại diện: $e');
    }
  }

  /// GET /api/v1/trips
  /// Fetches trips for calculating user travel statistics.
  Future<List<Map<String, dynamic>>> getUserTrips() async {
    try {
      final response = await _dio.get(
        '/api/v1/trips',
        queryParameters: {'limit': 50},
      );
      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic>) {
          final map = response.data as Map<String, dynamic>;
          if (map['items'] is List) {
            return (map['items'] as List)
                .whereType<Map<String, dynamic>>()
                .toList();
          }
        } else if (response.data is List) {
          return (response.data as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  ServerException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    String message;
    if (data is Map<String, dynamic> && data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is List) {
        message = detail.map((d) => d['msg'] ?? d.toString()).join(', ');
      } else {
        message = detail.toString();
      }
    } else {
      switch (statusCode) {
        case 401:
          message = 'Phiên đăng nhập đã hết hạn';
          break;
        case 403:
          message = 'Bạn không có quyền thực hiện thao tác này';
          break;
        case 404:
          message = 'Không tìm thấy dữ liệu người dùng';
          break;
        default:
          message = e.message ?? 'Đã xảy ra lỗi không xác định';
      }
    }
    return ServerException(message: message, statusCode: statusCode);
  }
}
