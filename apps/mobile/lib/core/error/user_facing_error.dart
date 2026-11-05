import 'package:dio/dio.dart';

String userFacingServerError(
  Object error, {
  String fallback = 'Không thể hoàn tất yêu cầu. Vui lòng thử lại sau.',
}) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    }
    if (statusCode == 404) {
      return 'Không tìm thấy dữ liệu yêu cầu. Vui lòng thử lại sau.';
    }
    if (statusCode == 422) {
      return 'Thông tin yêu cầu chưa hợp lệ. Vui lòng thử lại.';
    }
    if (statusCode != null && statusCode >= 500) {
      return 'Máy chủ đang bận. Vui lòng thử lại sau ít phút.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng và thử lại.';
    }
  }
  return fallback;
}
