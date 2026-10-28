import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/assistant/presentation/models/chat_media.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/chat_media_gallery.dart';
import 'package:mobile/features/assistant/presentation/widgets/chat_message_bubble.dart';
import 'package:mobile/features/assistant/presentation/widgets/chat_video_player.dart';

void main() {
  group('ChatMedia Model Tests', () {
    test('Correctly identifies image vs video', () {
      const img = ChatMedia(
        id: '1',
        type: ChatMediaType.image,
        url: 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
        title: 'Bà Nà Hills',
      );
      expect(img.isImage, isTrue);
      expect(img.isVideo, isFalse);
      expect(img.isYouTube, isFalse);

      const vid = ChatMedia(
        id: '2',
        type: ChatMediaType.video,
        url: 'https://www.youtube.com/watch?v=0hWqPz3f8hU',
        title: 'Đà Nẵng Travel Guide',
      );
      expect(vid.isImage, isFalse);
      expect(vid.isVideo, isTrue);
      expect(vid.isYouTube, isTrue);
      expect(vid.youtubeId, '0hWqPz3f8hU');
      expect(vid.resolvedThumbnailUrl, 'https://img.youtube.com/vi/0hWqPz3f8hU/hqdefault.jpg');
    });

    test('JSON serialization & deserialization', () {
      final json = {
        'id': 'med_123',
        'type': 'video',
        'url': 'https://example.com/video.mp4',
        'thumbnail_url': 'https://example.com/thumb.jpg',
        'title': 'Test Video',
      };

      final media = ChatMedia.fromJson(json);
      expect(media.id, 'med_123');
      expect(media.type, ChatMediaType.video);
      expect(media.url, 'https://example.com/video.mp4');
      expect(media.thumbnailUrl, 'https://example.com/thumb.jpg');
      expect(media.title, 'Test Video');

      final serialized = media.toJson();
      expect(serialized['type'], 'video');
      expect(serialized['id'], 'med_123');
    });

    test('ChatMessage backward compatibility without media', () {
      final msg = ChatMessage(
        text: 'Hello TravelWise',
        isUser: true,
        timestamp: DateTime.now(),
      );
      expect(msg.media, isEmpty);
      expect(msg.text, 'Hello TravelWise');
      expect(msg.isUser, isTrue);
    });

    test('ChatMessage with media attachments', () {
      const img = ChatMedia(
        id: 'm1',
        type: ChatMediaType.image,
        url: 'https://example.com/photo.jpg',
      );
      final msg = ChatMessage(
        text: 'Xem ảnh này',
        isUser: false,
        timestamp: DateTime.now(),
        media: [img],
      );
      expect(msg.media.length, 1);
      expect(msg.media.first.id, 'm1');
    });
  });

  group('Chat Media Widgets Tests', () {
    testWidgets('ChatMediaGallery renders video preview card with Play button',
        (tester) async {
      const vid = ChatMedia(
        id: 'v1',
        type: ChatMediaType.video,
        url: 'https://www.youtube.com/watch?v=0hWqPz3f8hU',
        title: 'Khám phá Đà Nẵng',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatMediaGallery(
              mediaList: [vid],
            ),
          ),
        ),
      );

      expect(find.byType(ChatVideoPreviewCard), findsOneWidget);
      expect(find.text('Khám phá Đà Nẵng'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
    });

    testWidgets('ChatMessageBubble renders text and ChatMediaGallery cleanly',
        (tester) async {
      const img = ChatMedia(
        id: 'i1',
        type: ChatMediaType.image,
        url: 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
        title: 'Cầu Vàng',
      );

      final msg = ChatMessage(
        text: 'Đây là hình ảnh Cầu Vàng bạn yêu cầu:',
        isUser: false,
        timestamp: DateTime(2026, 10, 28, 14, 30),
        media: [img],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(message: msg),
          ),
        ),
      );

      expect(find.text('Đây là hình ảnh Cầu Vàng bạn yêu cầu:'), findsOneWidget);
      expect(find.byType(ChatMediaGallery), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
    });
  });
}
