import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../models/chat_media.dart';
import 'chat_video_player.dart';
import 'fullscreen_media_viewer.dart';

/// Renders images and videos inside chat message bubbles.
/// Supports single image, multi-image horizontal carousel / grid, and video preview cards.
class ChatMediaGallery extends StatelessWidget {
  final List<ChatMedia> mediaList;
  final bool isUser;

  const ChatMediaGallery({
    super.key,
    required this.mediaList,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaList.isEmpty) return const SizedBox.shrink();

    final images = mediaList.where((m) => m.isImage).toList();
    final videos = mediaList.where((m) => m.isVideo).toList();

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Render Videos first or with preview cards ──────────────────────
        if (videos.isNotEmpty) ...[
          ...videos.map((vid) => ChatVideoPreviewCard(media: vid)),
          if (images.isNotEmpty) const SizedBox(height: 6),
        ],

        // ── Render Images ──────────────────────────────────────────────────
        if (images.length == 1)
          _buildSingleImage(context, images.first)
        else if (images.length > 1)
          _buildMultipleImages(context, images),
      ],
    );
  }

  Widget _buildSingleImage(BuildContext context, ChatMedia media) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => FullscreenMediaViewer.open(
              context,
              mediaList: [media],
              initialIndex: 0,
            ),
            child: Stack(
              children: [
                Image.network(
                  media.url,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 180,
                      color: AppColors.border.withValues(alpha: 0.3),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => _buildErrorCard(media.title),
                ),
                // Expand icon overlay
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMultipleImages(BuildContext context, List<ChatMedia> images) {
    return Container(
      height: 140,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = images[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => FullscreenMediaViewer.open(
                  context,
                  mediaList: images,
                  initialIndex: index,
                ),
                child: Stack(
                  children: [
                    Image.network(
                      item.url,
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: 140,
                          height: 140,
                          color: AppColors.border.withValues(alpha: 0.3),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => _buildSmallErrorCard(),
                    ),
                    // Image index badge
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}/${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorCard(String? title) {
    return Container(
      height: 160,
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_rounded, color: AppColors.textSecondary, size: 36),
            const SizedBox(height: 6),
            Text(
              title ?? 'Không thể tải ảnh',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallErrorCard() {
    return Container(
      width: 140,
      height: 140,
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(Icons.broken_image_rounded, color: AppColors.textSecondary, size: 28),
      ),
    );
  }
}
