import 'package:dio/dio.dart';
import '../../../../core/error/exceptions.dart';
import '../models/token_model.dart';
import '../models/user_model.dart';

/// Remote data source that communicates with the FastAPI backend.
/// This is the ONLY class allowed to make HTTP calls for auth.
class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  /// POST /api/v1/auth/login
  Future<TokenModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );
      return TokenModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// POST /api/v1/auth/register
  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
        },
      );
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// GET /api/v1/auth/me
  Future<UserModel> getCurrentUser() async {
    try {
      final response = await _dio.get('/api/v1/auth/me');
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Maps Dio errors to domain-friendly [ServerException]s.
  ServerException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    String message;
    if (data is Map<String, dynamic> && data.containsKey('detail')) {
      message = data['detail'].toString();
    } else {
      switch (statusCode) {
        case 401:
          message = 'Email hoặc mật khẩu không chính xác';
          break;
        case 403:
          message = 'Tài khoản đã bị vô hiệu hóa';
          break;
        case 409:
          message = 'Email đã được sử dụng';
          break;
        case 422:
          message = 'Dữ liệu không hợp lệ';
          break;
        default:
          message = e.message ?? 'Đã xảy ra lỗi không xác định';
      }
    }

    return ServerException(message: message, statusCode: statusCode);
  }
}
