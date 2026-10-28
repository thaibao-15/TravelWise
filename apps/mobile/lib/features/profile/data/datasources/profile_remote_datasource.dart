import 'package:dio/dio.dart';
import '../../../../core/error/exceptions.dart';
import '../../../auth/data/models/user_model.dart';

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

  ServerException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    String message;
    if (data is Map<String, dynamic> && data.containsKey('detail')) {
      message = data['detail'].toString();
    } else {
      switch (statusCode) {
        case 401:
          message = 'Phiên đăng nhập đã hết hạn';
          break;
        case 403:
          message = 'Bạn không có quyền thực hiện thao tác này';
          break;
        case 404:
          message = 'Không tìm thấy người dùng';
          break;
        default:
          message = e.message ?? 'Đã xảy ra lỗi không xác định';
      }
    }
    return ServerException(message: message, statusCode: statusCode);
  }
}
