import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/lip_sync_frame.dart';
import '../../services/avatar_animation_service.dart';
import '../models/glb_model.dart';
import '../providers/avatar_state_provider.dart';
import '../providers/voice_assistant_provider.dart';
import 'glb_3d_painter.dart';

/// Interactive 3D AI Tour Guide Avatar for TravelWise.
///
/// Features:
/// - Real-time 3D GLB rendering from `assets/models/linh_avatar.glb` (or any `.vrm` / `.glb` in assets)
/// - Seamless Voice AI state integration (Idle, Listening, Thinking, Speaking, Error)
/// - 60fps audio-driven Morph Target Lip Sync using Blaze TTS audio
/// - Autonomous blinking, gentle breathing, expressive nodding & hand gestures
/// - Interactive touch / mouse drag orbit rotation with 3D studio lighting halo
/// - 100% offline, zero network requests, free & cross-platform for Flutter Web and Android!
class Ai3dAvatar extends ConsumerStatefulWidget {
  final VoiceState voiceState;
  final ValueListenable<LipSyncFrame>? lipSyncListenable;
  final String speechText;
  final VoidCallback? onResetOrbit;

  const Ai3dAvatar({
    super.key,
    required this.voiceState,
    this.lipSyncListenable,
    this.speechText = '',
    this.onResetOrbit,
  });

  @override
  ConsumerState<Ai3dAvatar> createState() => _Ai3dAvatarState();
}

class _Ai3dAvatarState extends ConsumerState<Ai3dAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tickerController;
  final AvatarAnimationService _animationService = AvatarAnimationService();

  GlbModel? _loadedModel;
  bool _isLoading = true;
  String? _loadError;

  // Cached model bytes across widget rebuilds
  static GlbModel? _cachedModel;

  @override
  void initState() {
    super.initState();
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3600),
    )..repeat();

    _loadAvatarModel();
  }

  @override
  void dispose() {
    _tickerController.dispose();
    super.dispose();
  }

  Future<void> _loadAvatarModel() async {
    if (_cachedModel != null) {
      if (mounted) {
        setState(() {
          _loadedModel = _cachedModel;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(avatar3dStateProvider.notifier)
                .setLoaded(
                  modelName: _cachedModel!.name,
                  hasMorphTargets: _cachedModel!.hasMorphTargets,
                  hasSkeleton: _cachedModel!.hasSkeleton,
                );
          }
        });
      }
      return;
    }

    try {
      // 1. Prioritize AvatarSample_A 3D model
      final assetPaths = [
        'assets/models/AvatarSample_A.glb',
        'assets/models/AvatarSample_A.vrm',
        'assets/models/linh_avatar.glb',
        'assets/models/model.vrm',
        'assets/models/model.glb',
      ];

      ByteData? byteData;
      String chosenPath = '';

      for (final p in assetPaths) {
        try {
          byteData = await rootBundle.load(p);
          chosenPath = p;
          break;
        } catch (_) {
          // Continue searching fallback candidates
        }
      }

      if (byteData == null) {
        throw Exception(
          'Không tìm thấy tệp 3D (.glb / .vrm) khả dụng trong assets/models.',
        );
      }

      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      final model = GlbModel.fromBytes(bytes, name: 'AvatarSample_A');
      _cachedModel = model;

      if (mounted) {
        setState(() {
          _loadedModel = model;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(avatar3dStateProvider.notifier)
                .setLoaded(
                  modelName: chosenPath.split('/').last,
                  hasMorphTargets: model.hasMorphTargets,
                  hasSkeleton: model.hasSkeleton,
                );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(avatar3dStateProvider.notifier).setError(e.toString());
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarState = ref.watch(avatar3dStateProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // 1. Studio Stage Gradient Background & Ambient Lighting Ring
              _buildStudioBackground(context, widget.voiceState),

              // 2. Interactive 3D Model Rendering Viewport
              if (_isLoading)
                _buildLoadingIndicator()
              else if (_loadError != null)
                _buildErrorPlaceholder(_loadError!)
              else if (_loadedModel != null)
                GestureDetector(
                  onPanUpdate: (details) {
                    final deltaX =
                        details.delta.dx / constraints.maxWidth * 2.8;
                    final deltaY =
                        details.delta.dy / constraints.maxHeight * 2.0;
                    ref
                        .read(avatar3dStateProvider.notifier)
                        .addOrbitDelta(deltaYaw: deltaX, deltaPitch: -deltaY);
                  },
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _tickerController,
                      if (widget.lipSyncListenable != null)
                        widget.lipSyncListenable!,
                    ]),
                    builder: (context, child) {
                      final elapsed =
                          _tickerController
                              .lastElapsedDuration
                              ?.inMicroseconds ??
                          0;
                      final seconds = elapsed / 1000000.0;
                      final lipSync =
                          widget.lipSyncListenable?.value ?? LipSyncFrame.idle;

                      final frame = _animationService.computeFrame(
                        elapsedSeconds: seconds,
                        voiceState: widget.voiceState,
                        lipSync: lipSync,
                        speechText: widget.speechText,
                      );

                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: Glb3dPainter(
                          model: _loadedModel!,
                          frame: frame,
                          orbitYaw: avatarState.userOrbitYaw,
                          orbitPitch: avatarState.userOrbitPitch,
                          zoom: avatarState.userZoom,
                          cameraDistance: 0.94,
                          targetY: 1.29,
                        ),
                      );
                    },
                  ),
                ),

              // 3. Status Badge Overlay (Top-Left)
              Positioned(
                top: 14,
                left: 14,
                child: _buildAvatarStatusPill(widget.voiceState),
              ),

              // 4. Reset Orbit Camera Button (Top-Right)
              if (avatarState.userOrbitYaw.abs() > 0.05 ||
                  avatarState.userOrbitPitch.abs() > 0.05)
                Positioned(
                  top: 14,
                  right: 14,
                  child: InkWell(
                    onTap: () {
                      ref.read(avatar3dStateProvider.notifier).resetOrbit();
                      widget.onResetOrbit?.call();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.center_focus_strong,
                            color: Colors.white,
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Đặt lại góc nhìn',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 5. Subtle Soft Floor Gradient
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          const Color(0xFFF6F8FB).withValues(alpha: 0.15),
                          const Color(0xFFF6F8FB).withValues(alpha: 0.90),
                        ],
                        stops: const [0.0, 0.65, 0.88, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudioBackground(BuildContext context, VoiceState state) {
    Color ambientGlow;
    switch (state) {
      case VoiceState.speaking:
        ambientGlow = const Color(0xFF0284C7).withValues(alpha: 0.25);
        break;
      case VoiceState.listening:
        ambientGlow = const Color(0xFF10B981).withValues(alpha: 0.22);
        break;
      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        ambientGlow = const Color(0xFF0D9488).withValues(alpha: 0.25);
        break;
      case VoiceState.error:
        ambientGlow = const Color(0xFFEF4444).withValues(alpha: 0.20);
        break;
      case VoiceState.idle:
        ambientGlow = const Color(0xFF6366F1).withValues(alpha: 0.16);
        break;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.2),
          radius: 0.85,
          colors: [
            ambientGlow,
            const Color(0xFFE0E7FF).withValues(alpha: 0.35),
            const Color(0xFFF1F5F9),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  Widget _buildAvatarStatusPill(VoiceState state) {
    Color dotColor;
    String statusText;

    switch (state) {
      case VoiceState.speaking:
        dotColor = const Color(0xFF0284C7);
        statusText = 'Linh AI 3D • Đang nói';
        break;
      case VoiceState.listening:
        dotColor = const Color(0xFF10B981);
        statusText = 'Linh AI 3D • Đang nghe bạn';
        break;
      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        dotColor = const Color(0xFF0D9488);
        statusText = 'Linh AI 3D • Đang suy nghĩ';
        break;
      case VoiceState.error:
        dotColor = const Color(0xFFEF4444);
        statusText = 'Linh AI 3D • Trạng thái nghỉ';
        break;
      case VoiceState.idle:
        dotColor = const Color(0xFF10B981);
        statusText = 'Linh AI 3D • Giọng Nữ Đà Nẵng';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Đang tải nhân vật 3D...',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.view_in_ar_rounded,
                size: 36,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(height: 8),
              Text(
                'Lỗi hiển thị model 3D: $error',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
