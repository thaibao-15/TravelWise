import 'dart:developer';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../presentation/models/conversation_item.dart';

class ConversationApiService {
  final DioClient _dioClient;

  ConversationApiService(this._dioClient);

  Dio get _dio => _dioClient.dio;

  /// Fetch all conversations of the current authenticated user.
  Future<List<ConversationItem>> fetchUserConversations({int skip = 0, int limit = 50}) async {
    try {
      final response = await _dio.get(
        '/api/v1/conversations/',
        queryParameters: {'skip': skip, 'limit': limit},
      );

      if (response.statusCode == 200 && response.data is List) {
        final list = response.data as List;
        return list
            .map((item) => ConversationItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      log('fetch_conversations_error: ${e.message}');
      return [];
    } catch (e) {
      log('fetch_conversations_unexpected: $e');
      return [];
    }
  }

  /// Fetch message history for a specific conversation.
  Future<List<Map<String, dynamic>>> fetchConversationMessages(int conversationId) async {
    try {
      final response = await _dio.get('/api/v1/conversations/$conversationId/messages');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List).cast<Map<String, dynamic>>();
      }
      return [];
    } on DioException catch (e) {
      log('fetch_conversation_messages_error: ${e.message}');
      return [];
    } catch (e) {
      log('fetch_conversation_messages_unexpected: $e');
      return [];
    }
  }

  /// Delete a conversation by ID.
  Future<bool> deleteConversation(int conversationId) async {
    try {
      final response = await _dio.delete('/api/v1/conversations/$conversationId');
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      log('delete_conversation_error: ${e.message}');
      return false;
    } catch (e) {
      log('delete_conversation_unexpected: $e');
      return false;
    }
  }
}

