import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
/// - Real-time 3D GLB/VRM rendering from `assets/models/AvatarSample_A.glb`, `linh_avatar.glb`, etc.
/// - Dynamic model switching (switch between multiple 3D characters seamlessly)
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
  final VoidCallback? onOpenSettings;
  final String? customModelPath;

  const Ai3dAvatar({
    super.key,
    required this.voiceState,
    this.lipSyncListenable,
    this.speechText = '',
    this.onResetOrbit,
    this.onOpenSettings,
    this.customModelPath,
  });

  @override
  ConsumerState<Ai3dAvatar> createState() => _Ai3dAvatarState();
}

class _Ai3dAvatarState extends ConsumerState<Ai3dAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tickerController;
  final AvatarAnimationService _animationService = AvatarAnimationService();

  GlbModel? _loadedModel;
  List<ui.Image?>? _loadedTextures;
  bool _isLoading = true;
  String? _loadError;
  double _baseScaleZoom = 1.0;

  // Cached model & decoded GPU textures across widget rebuilds and character switches
  static final Map<String, GlbModel> _modelCache = {};
  static final Map<String, List<ui.Image?>> _textureCache = {};

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

  void _decodeAndCacheTextures(GlbModel model, List<String> cacheKeys) {
    if (!model.hasTextures) return;
    model.decodeTextures().then((decoded) {
      if (decoded.any((img) => img != null)) {
        for (final key in cacheKeys) {
          if (key.isNotEmpty) {
            _textureCache[key] = decoded;
          }
        }
      }
      if (mounted && identical(_loadedModel, model)) {
        setState(() {
          _loadedTextures = decoded;
        });
      }
    });
  }

  Future<void> _loadAvatarModel([String? targetPath]) async {
    final chosenPath = targetPath ??
        widget.customModelPath ??
        ref.read(avatar3dStateProvider).selectedModelPath;

    // Fast-path: grab from cache if available
    if (_modelCache.containsKey(chosenPath)) {
      final cached = _modelCache[chosenPath]!;
      final cachedTextures = _textureCache[chosenPath];
      if (mounted) {
        setState(() {
          _loadedModel = cached;
          _loadedTextures = cachedTextures;
          _isLoading = false;
          _loadError = null;
        });
        if (cachedTextures == null && cached.hasTextures) {
          _decodeAndCacheTextures(cached, [chosenPath]);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(avatar3dStateProvider.notifier)
                .setLoaded(
                  modelName: cached.name,
                  hasMorphTargets: cached.hasMorphTargets,
                  hasSkeleton: cached.hasSkeleton,
                );
          }
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final assetPaths = [
        chosenPath,
        'assets/models/Nam_C.glb',
        'assets/models/Nam_C.vrm',
        'assets/models/AvatarSample_A.glb',
        'assets/models/AvatarSample_A.vrm',
        'assets/models/model.vrm',
        'assets/models/model.glb',
      ];

      ByteData? byteData;
      String successfulPath = '';

      for (final p in assetPaths) {
        try {
          byteData = await rootBundle.load(p);
          successfulPath = p;
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

      final displayName = successfulPath
          .split('/')
          .last
          .replaceAll(RegExp(r'\.(glb|vrm)$'), '');
      final model = GlbModel.fromBytes(bytes, name: displayName);
      _modelCache[chosenPath] = model;
      _modelCache[successfulPath] = model;

      if (mounted) {
        setState(() {
          _loadedModel = model;
          _loadedTextures = _textureCache[successfulPath];
          _isLoading = false;
        });

        if (_loadedTextures == null && model.hasTextures) {
          _decodeAndCacheTextures(model, [chosenPath, successfulPath]);
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final option = kAvailableAvatars.firstWhere(
              (a) => a.assetPath == chosenPath || a.assetPath == successfulPath,
              orElse: () => Avatar3dOption(
                id: 'custom',
                name: displayName,
                subtitle: '',
                assetPath: chosenPath,
                tag: '',
              ),
            );
            ref
                .read(avatar3dStateProvider.notifier)
                .setLoaded(
                  modelName: option.name,
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
    // Listen for model switching from provider
    ref.listen<String>(
      avatar3dStateProvider.select((s) => s.selectedModelPath),
      (prev, next) {
        if (prev != next) {
          _loadAvatarModel(next);
        }
      },
    );

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
                Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      final currentZoom = ref.read(avatar3dStateProvider).userZoom;
                      ref
                          .read(avatar3dStateProvider.notifier)
                          .setZoom(currentZoom - event.scrollDelta.dy * 0.0012);
                    }
                  },
                  child: GestureDetector(
                    onScaleStart: (_) {
                      _baseScaleZoom = ref.read(avatar3dStateProvider).userZoom;
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount >= 2) {
                        ref
                            .read(avatar3dStateProvider.notifier)
                            .setZoom(_baseScaleZoom * details.scale);
                      } else {
                        final deltaX =
                            details.focalPointDelta.dx / constraints.maxWidth * 2.8;
                        final deltaY =
                            details.focalPointDelta.dy / constraints.maxHeight * 2.0;
                        ref.read(avatar3dStateProvider.notifier).addOrbitDelta(
                              deltaYaw: deltaX,
                              deltaPitch: -deltaY,
                            );
                      }
                    },
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _tickerController,
                        if (widget.lipSyncListenable != null)
                          widget.lipSyncListenable!,
                      ]),
                      builder: (context, child) {
                        final elapsed =
                            _tickerController.lastElapsedDuration?.inMicroseconds ?? 0;
                        final seconds = elapsed / 1000000.0;
                        final lipSync =
                            widget.lipSyncListenable?.value ?? LipSyncFrame.idle;

                        final frame = _animationService.computeFrame(
                          elapsedSeconds: seconds,
                          voiceState: widget.voiceState,
                          lipSync: lipSync,
                          speechText: widget.speechText,
                        );

                        final bool isSkinned = _loadedModel!.skins.isNotEmpty;
                        final bool isNam = _loadedModel!.name.toLowerCase().contains('nam');

                        // Góc cận cảnh chân dung bán thân (Bust-up Portrait):
                        // Cận mặt hơn thêm một nấc, làm nổi bật ánh mắt & khẩu hình nhưng vẫn giữ trọn bờ vai cân xứng
                        final double camDist = isSkinned ? 0.67 : 0.88;
                        final double tgtY = isSkinned
                            ? (isNam ? 1.50 : 1.32)
                            : 1.14;

                        return CustomPaint(
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                          painter: Glb3dPainter(
                            model: _loadedModel!,
                            textures: _loadedTextures,
                            frame: frame,
                            orbitYaw: avatarState.userOrbitYaw,
                            orbitPitch: avatarState.userOrbitPitch,
                            zoom: avatarState.userZoom,
                            cameraDistance: camDist,
                            targetY: tgtY,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // 3. Status Badge Overlay (Top-Left)
              Positioned(
                top: 14,
                left: 14,
                child: _buildAvatarStatusPill(widget.voiceState),
              ),

              // 4. Action Buttons (Top-Right: Settings / Change Character & Reset View)
              Positioned(
                top: 14,
                right: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onOpenSettings != null)
                      InkWell(
                        onTap: widget.onOpenSettings,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded, color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'Đổi 3D & Giọng',
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
                    if (avatarState.userOrbitYaw.abs() > 0.05 ||
                        avatarState.userOrbitPitch.abs() > 0.05 ||
                        (avatarState.userZoom - 1.0).abs() > 0.05) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          ref.read(avatar3dStateProvider.notifier).resetOrbit();
                          widget.onResetOrbit?.call();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.center_focus_strong, color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'Góc nhìn',
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
                    ],
                  ],
                ),
              ),

              // 5. Subtle Soft Floor Touch (Giữ trọn vẹn chi tiết trang phục, váy và bàn tay)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          const Color(0xFFF6F8FB).withValues(alpha: 0.22),
                        ],
                        stops: const [0.0, 0.92, 1.0],
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
    Color outerGlow;
    switch (state) {
      case VoiceState.speaking:
        ambientGlow = const Color(0xFF38BDF8).withValues(alpha: 0.28);
        outerGlow = const Color(0xFFBAE6FD).withValues(alpha: 0.20);
        break;
      case VoiceState.listening:
        ambientGlow = const Color(0xFF10B981).withValues(alpha: 0.24);
        outerGlow = const Color(0xFFA7F3D0).withValues(alpha: 0.18);
        break;
      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        ambientGlow = const Color(0xFF14B8A6).withValues(alpha: 0.26);
        outerGlow = const Color(0xFF99F6E4).withValues(alpha: 0.18);
        break;
      case VoiceState.error:
        ambientGlow = const Color(0xFFEF4444).withValues(alpha: 0.22);
        outerGlow = const Color(0xFFFECACA).withValues(alpha: 0.15);
        break;
      case VoiceState.idle:
        ambientGlow = const Color(0xFF6366F1).withValues(alpha: 0.18);
        outerGlow = const Color(0xFFE0E7FF).withValues(alpha: 0.15);
        break;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFE8F1FC),
            Color(0xFFF1F5F9),
            Color(0xFFF8FAFC),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Vòng hào quang Studio nổi bật sau lưng nhân vật (Backlight Halo)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.22),
                radius: 0.72,
                colors: [
                  ambientGlow,
                  outerGlow,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarStatusPill(VoiceState state) {
    Color dotColor;
    String statusText;

    final String avatarName = ref.watch(avatar3dStateProvider).modelName;

    switch (state) {
      case VoiceState.speaking:
        dotColor = const Color(0xFF0284C7);
        statusText = '$avatarName • Đang nói';
        break;
      case VoiceState.listening:
        dotColor = const Color(0xFF10B981);
        statusText = '$avatarName • Đang nghe bạn';
        break;
      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        dotColor = const Color(0xFF0D9488);
        statusText = '$avatarName • Đang suy nghĩ';
        break;
      case VoiceState.error:
        dotColor = const Color(0xFFEF4444);
        statusText = '$avatarName • Trạng thái nghỉ';
        break;
      case VoiceState.idle:
        dotColor = const Color(0xFF10B981);
        statusText = '$avatarName • Sẵn sàng';
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
