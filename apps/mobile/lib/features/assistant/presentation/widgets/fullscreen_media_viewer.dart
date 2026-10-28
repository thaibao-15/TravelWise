import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../models/chat_media.dart';

/// Fullscreen interactive image viewer supporting pinch-to-zoom, pan, and swipe across galleries.
class FullscreenMediaViewer extends StatefulWidget {
  final List<ChatMedia> mediaList;
  final int initialIndex;

  const FullscreenMediaViewer({
    super.key,
    required this.mediaList,
    this.initialIndex = 0,
  });

  static void open(
    BuildContext context, {
    required List<ChatMedia> mediaList,
    int initialIndex = 0,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenMediaViewer(
          mediaList: mediaList,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<FullscreenMediaViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.mediaList[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Swipeable image pages
            PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaList.length,
              onPageChanged: (idx) {
                setState(() {
                  _currentIndex = idx;
                  _resetZoom();
                });
              },
              itemBuilder: (context, index) {
                final media = widget.mediaList[index];
                return GestureDetector(
                  onDoubleTap: () {
                    if (_transformController.value != Matrix4.identity()) {
                      _resetZoom();
                    } else {
                      _transformController.value = Matrix4.diagonal3Values(2.2, 2.2, 1.0);
                    }
                  },
                  child: Center(
                    child: InteractiveViewer(
                      transformationController: index == _currentIndex ? _transformController : null,
                      minScale: 0.8,
                      maxScale: 4.5,
                      child: Image.network(
                        media.url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          final total = progress.expectedTotalBytes;
                          final current = progress.cumulativeBytesLoaded;
                          final ratio = total != null && total > 0 ? current / total : null;
                          return Center(
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                value: ratio,
                                strokeWidth: 2.5,
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.white54,
                                  size: 54,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Không thể tải hình ảnh này',
                                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  media.url,
                                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

            // Top navigation bar
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (currentItem.title != null && currentItem.title!.isNotEmpty)
                          Text(
                            currentItem.title!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (widget.mediaList.length > 1)
                          Text(
                            '${_currentIndex + 1} / ${widget.mediaList.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 20),
                    ),
                    tooltip: 'Đặt lại thu phóng',
                    onPressed: _resetZoom,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
