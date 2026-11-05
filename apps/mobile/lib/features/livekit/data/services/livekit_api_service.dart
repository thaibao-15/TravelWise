import 'package:dio/dio.dart';

import '../../../../core/network/dio_client.dart';
import '../models/livekit_token.dart';

class LiveKitApiService {
  final Dio _dio;

  LiveKitApiService(DioClient dioClient) : _dio = dioClient.dio;

  Future<LiveKitToken> createToken({
    int? conversationId,
    String? roomName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/livekit/token',
        data: <String, dynamic>{
          'conversation_id': ?conversationId,
          'room_name': ?roomName,
        },
      );

      final data = response.data;
      if (data == null) {
        throw const FormatException('LiveKit token response is empty.');
      }
      return LiveKitToken.fromJson(data);
    } on DioException catch (error) {
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']?.toString()
          : null;
      throw Exception(detail ?? 'Không thể tạo phiên LiveKit.');
    }
  }
}
