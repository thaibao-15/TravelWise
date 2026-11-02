import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/network/dio_client.dart';
import '../presentation/models/chat_media.dart';

class MediaUploadException implements Exception {
  final String message;
  MediaUploadException(this.message);

  @override
  String toString() => message;
}

class MediaUploadService {
  final Dio _dio;
  final ImagePicker _picker;

  static const int maxImageSizeBytes = 20 * 1024 * 1024; // 20 MB
  static const int maxVideoSizeBytes = 100 * 1024 * 1024; // 100 MB

  MediaUploadService({Dio? dio, ImagePicker? picker})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
              ),
            ),
        _picker = picker ?? ImagePicker();


  /// Helper to convert relative server URL to absolute URL
  static String resolveUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }

  /// Pick an image from the device gallery
  Future<XFile?> pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image == null) return null;

      final length = await image.length();
      if (length > maxImageSizeBytes) {
        throw MediaUploadException(
          'Hình ảnh quá lớn (${(length / (1024 * 1024)).toStringAsFixed(1)} MB). Vui lòng chọn ảnh dưới 20 MB.',
        );
      }
      return image;
    } on MediaUploadException {
      rethrow;
    } catch (e) {
      throw MediaUploadException('Không thể chọn hình ảnh: $e');
    }
  }

  /// Pick a video from the device gallery
  Future<XFile?> pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return null;

      final length = await video.length();
      if (length > maxVideoSizeBytes) {
        throw MediaUploadException(
          'Video quá lớn (${(length / (1024 * 1024)).toStringAsFixed(1)} MB). Vui lòng chọn video dưới 100 MB.',
        );
      }
      return video;
    } on MediaUploadException {
      rethrow;
    } catch (e) {
      throw MediaUploadException('Không thể chọn video: $e');
    }
  }

  /// Upload an XFile attachment to `/api/v1/media/upload`
  Future<ChatMedia> uploadAttachment(
    XFile file,
    ChatMediaType type, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      final length = bytes.length;
      final fileName = file.name.isNotEmpty ? file.name : (type == ChatMediaType.video ? 'video.mp4' : 'image.jpg');

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
        ),
        'media_type': type.name,
      });

      final response = await _dio.post(
        '/api/v1/media/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) {
            onProgress(sent / total);
          }
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final rawUrl = data['url']?.toString() ?? '';
        final resolvedUrl = resolveUrl(rawUrl);

        return ChatMedia(
          id: data['id']?.toString() ?? 'med_${DateTime.now().millisecondsSinceEpoch}',
          type: type,
          url: resolvedUrl,
          thumbnailUrl: data['thumbnail_url'] != null ? resolveUrl(data['thumbnail_url'].toString()) : (type == ChatMediaType.image ? resolvedUrl : null),
          title: data['title']?.toString() ?? fileName,
          fileSize: length,
          mimeType: data['mime_type']?.toString(),
          isLocal: false,
        );
      } else {
        throw MediaUploadException('Tải tệp lên máy chủ thất bại (${response.statusCode})');
      }
    } on DioException catch (e) {
      final detail = e.response?.data?['detail']?.toString() ?? e.message;
      throw MediaUploadException('Lỗi mạng khi tải lên: $detail');
    } catch (e) {
      if (e is MediaUploadException) rethrow;
      throw MediaUploadException('Lỗi tải tệp: $e');
    }
  }
}
