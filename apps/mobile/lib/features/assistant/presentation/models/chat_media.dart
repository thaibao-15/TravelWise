import 'package:image_picker/image_picker.dart';

enum ChatMediaType {
  image,
  video,
}

class ChatMedia {
  final String id;
  final ChatMediaType type;
  final String url;
  final String? thumbnailUrl;
  final String? title;
  final int? fileSize;
  final String? mimeType;
  final bool isLocal;
  final XFile? localFile;

  const ChatMedia({
    required this.id,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.title,
    this.fileSize,
    this.mimeType,
    this.isLocal = false,
    this.localFile,
  });

  bool get isVideo => type == ChatMediaType.video;
  bool get isImage => type == ChatMediaType.image;

  /// Check if the video is a YouTube link
  bool get isYouTube {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  /// Extracts YouTube video ID if applicable
  String? get youtubeId {
    if (!isYouTube) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    return uri.queryParameters['v'];
  }

  /// Resolved thumbnail URL (defaults to high-res YouTube thumbnail if YouTube video)
  String? get resolvedThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl;
    }
    final ytId = youtubeId;
    if (ytId != null) {
      return 'https://img.youtube.com/vi/$ytId/hqdefault.jpg';
    }
    if (isImage) {
      return url;
    }
    return null;
  }

  factory ChatMedia.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString().toLowerCase();
    final isVid = rawType == 'video';
    return ChatMedia(
      id: (json['id'] ?? json['media_id'] ?? '').toString(),
      type: isVid ? ChatMediaType.video : ChatMediaType.image,
      url: json['url']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString(),
      title: json['title']?.toString(),
      fileSize: (json['file_size'] as num?)?.toInt(),
      mimeType: json['mime_type']?.toString(),
      isLocal: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'url': url,
      'thumbnail_url': thumbnailUrl,
      'title': title,
      if (fileSize != null) 'file_size': fileSize,
      if (mimeType != null) 'mime_type': mimeType,
    };
  }

  ChatMedia copyWith({
    String? id,
    ChatMediaType? type,
    String? url,
    String? thumbnailUrl,
    String? title,
    int? fileSize,
    String? mimeType,
    bool? isLocal,
    XFile? localFile,
  }) {
    return ChatMedia(
      id: id ?? this.id,
      type: type ?? this.type,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      title: title ?? this.title,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      isLocal: isLocal ?? this.isLocal,
      localFile: localFile ?? this.localFile,
    );
  }
}
