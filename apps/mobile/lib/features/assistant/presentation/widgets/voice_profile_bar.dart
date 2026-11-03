import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/avatar_state_provider.dart';
import '../providers/voice_assistant_provider.dart';
import 'avatar_voice_settings_sheet.dart';

/// Voice & 3D Avatar profile bar:
/// - Displays current 3D avatar & TTS voice settings dynamically.
/// - Tap to open `AvatarVoiceSettingsSheet` and switch character / voice in real-time.
class VoiceProfileBar extends ConsumerWidget {
  final VoidCallback? onTap;

  const VoiceProfileBar({super.key, this.onTap});

  String _formatVoiceName(String speakerId) {
    switch (speakerId) {
      case 'DaNang-Nu-1-BL':
        return 'Nữ Đà Nẵng';
      case 'HaNoi-Nu-1-BL':
        return 'Nữ Hà Nội';
      case 'HaNoi-Nam-1-BL':
        return 'Nam Hà Nội';
      case 'SaiGon-Nu-1-BL':
        return 'Nữ Sài Gòn';
      case 'SaiGon-Nam-1-BL':
        return 'Nam Sài Gòn';
      case 'Hue-Nu-1-BL':
        return 'Nữ Huế';
      default:
        return 'Nữ Đà Nẵng';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceAssistantProvider);
    final avatarState = ref.watch(avatar3dStateProvider);

    final voiceName = _formatVoiceName(voiceState.speakerId);
    final speed = voiceState.ttsSpeed;
    final avatarLabel = avatarState.modelName.replaceAll(' (3D Tour Guide)', '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () => AvatarVoiceSettingsSheet.show(context),
          borderRadius: BorderRadius.circular(32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Mic icon with gradient
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$avatarLabel • $voiceName • ${speed}x',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Tune / Settings chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 12, color: AppColors.primary),
                      SizedBox(width: 3),
                      Text(
                        'Đổi',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
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
}
