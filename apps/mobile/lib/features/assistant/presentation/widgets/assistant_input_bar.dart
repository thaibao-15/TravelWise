import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';

/// Bottom input composer: volume | text field | mic | send.
class AssistantInputBar extends ConsumerStatefulWidget {
  const AssistantInputBar({super.key});

  @override
  ConsumerState<AssistantInputBar> createState() =>
      _AssistantInputBarState();
}

class _AssistantInputBarState extends ConsumerState<AssistantInputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  late AnimationController _micPulse;
  late Animation<double> _micScale;

  @override
  void initState() {
    super.initState();
    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _micScale = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _micPulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _micPulse.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    ref.read(voiceAssistantProvider.notifier).sendMessage(text);
  }

  void _toggleMic() {
    final notifier = ref.read(voiceAssistantProvider.notifier);
    notifier.toggleRecording();
    final isRecording =
        ref.read(voiceAssistantProvider).isRecording;
    if (isRecording) {
      _micPulse.repeat(reverse: true);
    } else {
      _micPulse.stop();
      _micPulse.animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom:
            MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Volume / Mute button ─────────────────────────────────────────
          GestureDetector(
            onTap: notifier.toggleMute,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: state.isMuted
                    ? AppColors.error.withOpacity(0.1)
                    : AppColors.border.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                state.isMuted ? Icons.volume_off : Icons.volume_up,
                size: 20,
                color: state.isMuted
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── Text input ───────────────────────────────────────────────────
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _textCtrl,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Hỏi bất kỳ điều gì về chuyến đi...',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Mic button ───────────────────────────────────────────────────
          GestureDetector(
            onTap: _toggleMic,
            child: ScaleTransition(
              scale: _micScale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.isRecording
                      ? AppColors.error
                      : AppColors.border.withOpacity(0.5),
                  boxShadow: state.isRecording
                      ? [
                          BoxShadow(
                            color: AppColors.error.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ]
                      : [],
                ),
                child: Icon(
                  state.isRecording ? Icons.mic : Icons.mic_none,
                  size: 20,
                  color: state.isRecording
                      ? Colors.white
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Send button ──────────────────────────────────────────────────
          GestureDetector(
            onTap: state.voiceState == VoiceState.thinking
                ? null
                : _handleSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: state.voiceState == VoiceState.thinking
                    ? const LinearGradient(
                        colors: [Color(0xFFCBD5E1), Color(0xFFCBD5E1)])
                    : const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.secondary
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                boxShadow: state.voiceState == VoiceState.thinking
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: state.voiceState == VoiceState.thinking
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
