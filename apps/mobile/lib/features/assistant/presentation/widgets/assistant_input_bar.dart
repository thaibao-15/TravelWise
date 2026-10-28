import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';

/// Bottom bar: by default displays ONE SINGLE VOICE BUTTON for speaking with AI.
/// Provides an optional quick toggle to keyboard mode if text input is needed.
class AssistantInputBar extends ConsumerStatefulWidget {
  final bool allowKeyboardToggle;
  final String? defaultPromptLabel;

  const AssistantInputBar({
    super.key,
    this.allowKeyboardToggle = true,
    this.defaultPromptLabel,
  });

  @override
  ConsumerState<AssistantInputBar> createState() => _AssistantInputBarState();
}

class _AssistantInputBarState extends ConsumerState<AssistantInputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  late AnimationController _micPulse;
  late Animation<double> _micScale;
  bool _isKeyboardMode = false;

  @override
  void initState() {
    super.initState();
    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _micScale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _micPulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _micPulse.dispose();
    super.dispose();
  }

  void _syncMicPulse(bool isRecording) {
    if (isRecording) {
      if (!_micPulse.isAnimating) {
        _micPulse.repeat(reverse: true);
      }
    } else if (_micPulse.isAnimating || _micPulse.value != 0) {
      _micPulse.stop();
      _micPulse.animateTo(0);
    }
  }

  void _handleSend() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    ref.read(voiceAssistantProvider.notifier).sendMessage(text);
  }

  void _handleVoiceAction() {
    final state = ref.read(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    if (state.voiceState == VoiceState.speaking) {
      notifier.stopAudio();
      return;
    }
    notifier.toggleRecording();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VoiceAssistantState>(voiceAssistantProvider, (previous, next) {
      final micActive = next.isRecording ||
          next.voiceState == VoiceState.listening ||
          next.voiceState == VoiceState.connecting;
      _syncMicPulse(micActive);
    });

    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);
    final isSpeaking = state.voiceState == VoiceState.speaking;
    final isThinking = state.voiceState == VoiceState.thinking;
    final micActive = state.isRecording ||
        state.voiceState == VoiceState.listening ||
        state.voiceState == VoiceState.connecting;

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isKeyboardMode
            ? _buildKeyboardInputRow(state, notifier)
            : _buildSingleVoiceButtonRow(state, isSpeaking, isThinking, micActive),
      ),
    );
  }

  /// Mode 1 (DEFAULT): 1 nút duy nhất chỉ để nói chuyện với AI
  Widget _buildSingleVoiceButtonRow(
    VoiceAssistantState state,
    bool isSpeaking,
    bool isThinking,
    bool micActive,
  ) {
    return Row(
      key: const ValueKey('voice_mode'),
      children: [
        // ── 1 nút duy nhất chỉ để nói ──────────────────────────────────────
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isThinking ? null : _handleVoiceAction,
              borderRadius: BorderRadius.circular(28),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 50,
                decoration: BoxDecoration(
                  gradient: isSpeaking || micActive
                      ? const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        )
                      : (isThinking
                          ? const LinearGradient(
                              colors: [Color(0xFF94A3B8), Color(0xFF64748B)],
                            )
                          : const LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (isSpeaking || micActive
                              ? const Color(0xFFEF4444)
                              : AppColors.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isThinking) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'AI đang suy nghĩ...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (isSpeaking) ...[
                      const Icon(Icons.stop_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Dừng đọc AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ] else if (micActive) ...[
                      ScaleTransition(
                        scale: _micScale,
                        child: const Icon(Icons.mic, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Đang nghe... Chạm để gửi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        widget.defaultPromptLabel ?? 'Nhấn để nói chuyện với AI',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),

        // Optional keyboard toggle button on the side
        if (widget.allowKeyboardToggle) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => setState(() => _isKeyboardMode = true),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.keyboard_alt_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Mode 2 (Tùy chọn): Nhập văn bản khi người dùng bấm vào icon bàn phím
  Widget _buildKeyboardInputRow(
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    return Row(
      key: const ValueKey('keyboard_mode'),
      children: [
        // Button switch back to Voice Button
        GestureDetector(
          onTap: () => setState(() => _isKeyboardMode = false),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Text field
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _textCtrl,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Nhập câu hỏi cho AI...',
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

        // Send button
        GestureDetector(
          onTap: state.voiceState == VoiceState.thinking ? null : _handleSend,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: state.voiceState == VoiceState.thinking
                  ? const LinearGradient(
                      colors: [Color(0xFFCBD5E1), Color(0xFFCBD5E1)])
                  : const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: state.voiceState == VoiceState.thinking
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: state.voiceState == VoiceState.thinking
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }
}
