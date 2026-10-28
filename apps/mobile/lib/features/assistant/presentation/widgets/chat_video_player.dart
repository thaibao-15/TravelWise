import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/colors.dart';
import '../models/chat_media.dart';

/// Modal dialog player for direct MP4 video URLs.
/// Manages VideoPlayerController lifecycle, no autoplay until initialized,
/// pauses on exit and disposes resources cleanly.
class DirectVideoPlayerModal extends StatefulWidget {
  final ChatMedia media;

  const DirectVideoPlayerModal({super.key, required this.media});

  static void show(BuildContext context, ChatMedia media) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => DirectVideoPlayerModal(media: media),
    );
  }

  @override
  State<DirectVideoPlayerModal> createState() => _DirectVideoPlayerModalState();
}

class _DirectVideoPlayerModalState extends State<DirectVideoPlayerModal> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final uri = Uri.parse(widget.media.url);
      _controller = VideoPlayerController.networkUrl(uri);
      await _controller.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
      // Start playback after user requested play
      _controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.pause();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: const Color(0xFF0F172A),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: const Color(0xFF1E293B),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.media.title ?? 'Video du lịch',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Player view
              AspectRatio(
                aspectRatio: _isInitialized ? _controller.value.aspectRatio : 16 / 9,
                child: _hasError
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 42),
                              const SizedBox(height: 8),
                              const Text(
                                'Không thể phát video',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _errorMessage,
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                      )
                    : (!_isInitialized
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              VideoPlayer(_controller),
                              // Floating play/pause overlay
                              Center(
                                child: ValueListenableBuilder<VideoPlayerValue>(
                                  valueListenable: _controller,
                                  builder: (context, value, _) {
                                    if (value.isPlaying) return const SizedBox.shrink();
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        iconSize: 48,
                                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                                        onPressed: () => _controller.play(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Progress bar
                              VideoProgressIndicator(
                                _controller,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                colors: const VideoProgressColors(
                                  playedColor: AppColors.primary,
                                  bufferedColor: Colors.white30,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ],
                          )),
              ),

              // Controls row
              if (_isInitialized)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: const Color(0xFF1E293B),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final pos = value.position;
                      final dur = value.duration;
                      final posStr = '${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')}';
                      final durStr = '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';

                      return Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              value.isPlaying ? _controller.pause() : _controller.play();
                            },
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$posStr / $durStr',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              value.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _controller.setVolume(value.volume > 0 ? 0.0 : 1.0);
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Video card widget shown inside chat bubbles with preview thumbnail, title and Play button.
class ChatVideoPreviewCard extends StatelessWidget {
  final ChatMedia media;

  const ChatVideoPreviewCard({super.key, required this.media});

  Future<void> _handlePlay(BuildContext context) async {
    if (media.isYouTube) {
      final uri = Uri.parse(media.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể mở liên kết YouTube')),
          );
        }
      }
    } else {
      // Direct MP4 URL
      DirectVideoPlayerModal.show(context, media);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = media.resolvedThumbnailUrl;
    final isYt = media.isYouTube;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handlePlay(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Video thumbnail with play button overlay
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumbUrl != null && thumbUrl.isNotEmpty)
                        Image.network(
                          thumbUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: const Color(0xFF1E293B),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
                        )
                      else
                        _buildFallbackThumbnail(),

                      // Dark subtle gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.65),
                            ],
                          ),
                        ),
                      ),

                      // Centered Play Button
                      Center(
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isYt ? const Color(0xFFFF0000) : AppColors.primary,
                            boxShadow: [
                              BoxShadow(
                                color: (isYt ? const Color(0xFFFF0000) : AppColors.primary)
                                    .withValues(alpha: 0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),

                      // Platform Badge (YouTube or Video)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isYt ? Icons.smart_display_rounded : Icons.videocam_rounded,
                                size: 12,
                                color: isYt ? const Color(0xFFFF4444) : Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isYt ? 'YouTube' : 'Video HD',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Title and subtitle footer
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          media.title ?? (isYt ? 'Xem video trên YouTube' : 'Video du lịch'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isYt ? Icons.open_in_new_rounded : Icons.play_circle_outline_rounded,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.movie_creation_outlined, color: Colors.white30, size: 40),
      ),
    );
  }
}
