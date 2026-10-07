import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum VoiceState { listening, thinking, speaking }

// ─── Chat Message Model ───────────────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

// ─── State ────────────────────────────────────────────────────────────────────

class VoiceAssistantState {
  final VoiceState voiceState;
  final bool isMuted;
  final bool isRecording;
  final bool isConversationExpanded;
  final String currentTranscript;
  final List<ChatMessage> messages;
  final String selectedLanguage;

  const VoiceAssistantState({
    this.voiceState = VoiceState.listening,
    this.isMuted = false,
    this.isRecording = false,
    this.isConversationExpanded = false,
    this.currentTranscript =
        'Gợi ý cho mình quán cà phê view biển đẹp gần Mỹ Khê để ngắm hoàng hôn chiều nay nhé?',
    this.messages = const [],
    this.selectedLanguage = 'VN',
  });

  VoiceAssistantState copyWith({
    VoiceState? voiceState,
    bool? isMuted,
    bool? isRecording,
    bool? isConversationExpanded,
    String? currentTranscript,
    List<ChatMessage>? messages,
    String? selectedLanguage,
  }) {
    return VoiceAssistantState(
      voiceState: voiceState ?? this.voiceState,
      isMuted: isMuted ?? this.isMuted,
      isRecording: isRecording ?? this.isRecording,
      isConversationExpanded:
          isConversationExpanded ?? this.isConversationExpanded,
      currentTranscript: currentTranscript ?? this.currentTranscript,
      messages: messages ?? this.messages,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class VoiceAssistantNotifier extends StateNotifier<VoiceAssistantState> {
  VoiceAssistantNotifier()
      : super(VoiceAssistantState(messages: _initialMessages()));

  static List<ChatMessage> _initialMessages() => [
        ChatMessage(
          text:
              'Tìm giúp mình chỗ uống cà phê ven biển Mỹ Khê yên tĩnh, có đồ uống ngon?',
          isUser: true,
          timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
        ChatMessage(
          text:
              'Mình đề xuất Cà phê Trình - Bãi Biển (cách bạn 850m) hoặc Paradise Beach Lounge. Chiều nay trời trong xanh, 28°C, hoàng hôn buông đẹp nhất lúc 17:45! ☀️',
          isUser: false,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      ];

  // Toggle voice state cycling: listening → thinking → speaking → listening
  void cycleVoiceState() {
    final next = switch (state.voiceState) {
      VoiceState.listening => VoiceState.thinking,
      VoiceState.thinking => VoiceState.speaking,
      VoiceState.speaking => VoiceState.listening,
    };
    state = state.copyWith(voiceState: next);
  }

  void setVoiceState(VoiceState vs) {
    state = state.copyWith(voiceState: vs);
  }

  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  void toggleRecording() {
    state = state.copyWith(isRecording: !state.isRecording);
  }

  void toggleConversation() {
    state = state.copyWith(
        isConversationExpanded: !state.isConversationExpanded);
  }

  void toggleLanguage() {
    final next = state.selectedLanguage == 'VN' ? 'EN' : 'VN';
    state = state.copyWith(selectedLanguage: next);
  }

  void setTranscript(String text) {
    state = state.copyWith(currentTranscript: text);
  }

  /// Mock send: add user message → thinking → AI response → speaking → listening
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMsg = ChatMessage(
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      voiceState: VoiceState.thinking,
      currentTranscript: text.trim(),
    );

    await Future.delayed(const Duration(milliseconds: 1400));

    const mockAiResponse =
        'Mình đề xuất Cà phê Trình - Bãi Biển (cách bạn 850m) hoặc Paradise Beach Lounge. Chiều nay trời trong xanh, 28°C, hoàng hôn buông đẹp nhất lúc 17:45! ☀️';

    final aiMsg = ChatMessage(
      text: mockAiResponse,
      isUser: false,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, aiMsg],
      voiceState: VoiceState.speaking,
    );

    await Future.delayed(const Duration(seconds: 2));

    state = state.copyWith(voiceState: VoiceState.listening);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final voiceAssistantProvider =
    StateNotifierProvider<VoiceAssistantNotifier, VoiceAssistantState>(
  (ref) => VoiceAssistantNotifier(),
);
