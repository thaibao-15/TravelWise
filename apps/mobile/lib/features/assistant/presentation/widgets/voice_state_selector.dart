import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';

/// Segmented control to switch between Listening / Thinking / Speaking states.
class VoiceStateSelector extends ConsumerWidget {
  const VoiceStateSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.border.withOpacity(0.6),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: VoiceState.values.map((vs) {
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
                              color: Colors.black.withOpacity(0.07),
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

  String _stateLabel(VoiceState vs) => switch (vs) {
        VoiceState.listening => 'Lắng nghe',
        VoiceState.thinking => 'Xử lý',
        VoiceState.speaking => 'Đang nói',
      };

  Color _stateColor(VoiceState vs) => switch (vs) {
        VoiceState.listening => AppColors.primary,
        VoiceState.thinking => AppColors.secondary,
        VoiceState.speaking => AppColors.success,
      };
}
