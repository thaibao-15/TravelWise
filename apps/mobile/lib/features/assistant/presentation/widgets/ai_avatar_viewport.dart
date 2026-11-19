import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/lip_sync_frame.dart';
import '../providers/avatar_state_provider.dart';
import '../providers/voice_assistant_provider.dart';
import 'ai_2d_avatar.dart';
import 'ai_3d_avatar.dart';
import 'avatar_voice_settings_sheet.dart';

/// Unified AI Tour Guide Viewport supporting dynamic seamless switching between
/// 2D Realistic Talking Photo (`assets/images/hdv.png`) and 3D glTF Models (`Nam_C.glb`, `AvatarSample_A.glb`).
///
/// Features:
/// - Smooth animated crossfade between 2D and 3D modes without interrupting ongoing Voice AI
/// - Shared 60fps audio-driven lip sync and Vietnamese phonetic timeline
/// - Mode Switcher pill (`[ 🖼️ Ảnh AI | 🧊 3D ]`) with persistence across app restarts
/// - Responsive voice state indicators (Idle, Listening, Thinking, Speaking)
/// - Integrated quick settings and camera orbit controls
class AiAvatarViewport extends ConsumerWidget {
  final VoiceState voiceState;
  final ValueListenable<LipSyncFrame>? lipSyncListenable;
  final String speechText;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onResetOrbit;
  final String photoPath;
  final double ttsSpeed;

  const AiAvatarViewport({
    super.key,
    required this.voiceState,
    this.lipSyncListenable,
    this.speechText = '',
    this.onOpenSettings,
    this.onResetOrbit,
    this.photoPath = 'assets/images/hdv.png',
    this.ttsSpeed = 1.5,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarState = ref.watch(avatar3dStateProvider);
    final avatarNotifier = ref.read(avatar3dStateProvider.notifier);
    final effectivePhoto = photoPath != 'assets/images/hdv.png'
        ? photoPath
        : avatarState.selectedPhotoPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Dynamic Mode View (2D Talking Photo <-> 3D Character)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: avatarState.is2dMode
                ? Ai2dAvatar(
                    key: const ValueKey('avatar_viewport_2d'),
                    voiceState: voiceState,
                    speechText: speechText,
                    lipSyncListenable: lipSyncListenable,
                    imagePath: effectivePhoto,
                    ttsSpeed: ttsSpeed,
                  )
                : Ai3dAvatar(
                    key: const ValueKey('avatar_viewport_3d'),
                    voiceState: voiceState,
                    speechText: speechText,
                    lipSyncListenable: lipSyncListenable,
                    showControls: false,
                  ),
          ),

          // 3. Top-Right Action Controls (Settings)
          Positioned(
            top: 14,
            right: 14,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Settings & Voice Options Button (Circle icon only)
                InkWell(
                  onTap: onOpenSettings ?? () => AvatarVoiceSettingsSheet.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.tune_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),

                // 3D Reset Orbit Button (only visible when in 3D mode and rotated/zoomed)
                if (avatarState.is3dMode &&
                    (avatarState.userOrbitYaw.abs() > 0.05 ||
                        avatarState.userOrbitPitch.abs() > 0.05 ||
                        (avatarState.userZoom - 1.0).abs() > 0.05)) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      avatarNotifier.resetOrbit();
                      onResetOrbit?.call();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
        ],
      ),
    );
  }

  /// Compact mode switcher segmented button: `[ 🖼️ Ảnh AI | 🧊 3D ]`
  Widget _buildModeSwitcherPill(
    Avatar3dState avatarState,
    Avatar3dNotifier avatarNotifier,
  ) {
    final is2d = avatarState.is2dMode;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentItem(
            label: 'Ảnh AI',
            icon: Icons.image_rounded,
            isSelected: is2d,
            onTap: () => avatarNotifier.setDisplayMode(AvatarDisplayMode.photo2d),
          ),
          const SizedBox(width: 2),
          _buildSegmentItem(
            label: '3D',
            icon: Icons.view_in_ar_rounded,
            isSelected: !is2d,
            onTap: () => avatarNotifier.setDisplayMode(AvatarDisplayMode.model3d),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStatusPill(Avatar3dState avatarState, VoiceState state) {
    Color dotColor;
    String statusText;

    // Chỉ hiển thị tên trợ lý và trạng thái đơn giản, bỏ hoàn toàn hậu tố kỹ thuật (Ảnh 2D / 3D)
    final String displayName = 'Linh AI';

    switch (state) {
      case VoiceState.speaking:
        dotColor = const Color(0xFF0284C7);
        statusText = '$displayName • Đang nói';
        break;
      case VoiceState.listening:
        dotColor = const Color(0xFF10B981);
        statusText = '$displayName • Đang nghe bạn';
        break;
      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        dotColor = const Color(0xFF0D9488);
        statusText = '$displayName • Đang suy nghĩ';
        break;
      case VoiceState.error:
        dotColor = const Color(0xFFEF4444);
        statusText = '$displayName • Nghỉ ngơi';
        break;
      case VoiceState.idle:
        dotColor = const Color(0xFF10B981);
        statusText = '$displayName • Sẵn sàng';
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
}

