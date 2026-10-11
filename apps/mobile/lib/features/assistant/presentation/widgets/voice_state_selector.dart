import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';

/// Segmented control showing only the 3 user-visible states:
/// Listening / Thinking / Speaking.
/// Other transient states (idle, connecting, etc.) are not shown as tabs.
class VoiceStateSelector extends ConsumerWidget {
  const VoiceStateSelector({super.key});

  // Only the 3 states the user can manually set via this widget
  static const _displayedStates = [
    VoiceState.listening,
    VoiceState.thinking,
    VoiceState.speaking,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: _displayedStates.map((vs) {
            final selected = state.voiceState == vs;
            return Expanded(
              child: GestureDetector(
                onTap: () => notifier.setVoiceState(vs),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _stateColor(vs),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                        child: Text(_stateLabel(vs)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _stateLabel(VoiceState vs) {
    switch (vs) {
      case VoiceState.listening:
        return 'Lắng nghe';
      case VoiceState.thinking:
        return 'Xử lý';
      case VoiceState.speaking:
        return 'Đang nói';
      default:
        return '';
    }
  }

  Color _stateColor(VoiceState vs) {
    switch (vs) {
      case VoiceState.listening:
        return AppColors.primary;
      case VoiceState.thinking:
        return AppColors.secondary;
      case VoiceState.speaking:
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }
}
