import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../providers/voice_assistant_provider.dart';

/// Displays the current voice transcript text + animated 3-dot indicator.
class TranscriptView extends ConsumerWidget {
  const TranscriptView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAssistantProvider);
    final displayText = _displayText(state);

    return Column(
      children: [
        // Transcript / status / error text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              displayText,
              key: ValueKey(displayText),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: state.error != null && state.error!.isNotEmpty
                    ? AppColors.error
                    : AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Animated 3-dot indicator
        const _AnimatedDots(),
      ],
    );
  }

  String _displayText(VoiceAssistantState state) {
    if (state.error != null && state.error!.isNotEmpty) {
      return state.error!;
    }
    if (state.currentTranscript.trim().isNotEmpty) {
      return state.currentTranscript;
    }
    switch (state.voiceState) {
      case VoiceState.connecting:
        return 'Đang kết nối nhận dạng giọng nói...';
      case VoiceState.listening:
        return 'Đang nghe... hãy nói tiếng Việt';
      case VoiceState.processing:
        return 'Đang xử lý câu nói...';
      case VoiceState.thinking:
        return 'AI đang suy nghĩ...';
      case VoiceState.speaking:
        return 'AI đang trả lời...';
      case VoiceState.error:
        return 'Có lỗi xảy ra. Thử nhấn micro lại.';
      case VoiceState.idle:
        return 'Nhấn micro để bắt đầu nói';
    }
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
        return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            // Bounce up and down
            final offset = -4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                offset: Offset(0, offset),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.5 + t * 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
