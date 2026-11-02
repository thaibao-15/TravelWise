import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../auth/auth_di.dart';
import '../../data/services/livekit_api_service.dart';

enum LiveKitVoiceState {
  disconnected,
  connecting,
  ready,
  listening,
  analyzing,
  speaking,
  muted,
  reconnecting,
  error,
}

class LiveKitVoiceStateModel {
  final LiveKitVoiceState state;
  final String? error;
  final String userTranscript;
  final String assistantTranscript;
  final bool microphoneEnabled;
  final int? conversationId;

  const LiveKitVoiceStateModel({
    this.state = LiveKitVoiceState.disconnected,
    this.error,
    this.userTranscript = '',
    this.assistantTranscript = '',
    this.microphoneEnabled = false,
    this.conversationId,
  });

  LiveKitVoiceStateModel copyWith({
    LiveKitVoiceState? state,
    String? error,
    bool clearError = false,
    String? userTranscript,
    String? assistantTranscript,
    bool? microphoneEnabled,
    int? conversationId,
  }) {
    return LiveKitVoiceStateModel(
      state: state ?? this.state,
      error: clearError ? null : (error ?? this.error),
      userTranscript: userTranscript ?? this.userTranscript,
      assistantTranscript: assistantTranscript ?? this.assistantTranscript,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      conversationId: conversationId ?? this.conversationId,
    );
  }
}

final liveKitApiServiceProvider = Provider<LiveKitApiService>((ref) {
  return LiveKitApiService(ref.watch(dioClientProvider));
});

final liveKitVoiceProvider =
    StateNotifierProvider<LiveKitVoiceNotifier, LiveKitVoiceStateModel>((ref) {
      final notifier = LiveKitVoiceNotifier(
        ref.watch(liveKitApiServiceProvider),
      );
      ref.onDispose(notifier.dispose);
      return notifier;
    });

class LiveKitVoiceNotifier extends StateNotifier<LiveKitVoiceStateModel> {
  final LiveKitApiService _apiService;
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  CancelListenFunc? _cancelRoomListener;

  LiveKitVoiceNotifier(this._apiService)
    : super(const LiveKitVoiceStateModel());

  Future<void> connect({int? conversationId}) async {
    if (state.state == LiveKitVoiceState.connecting ||
        _room?.connectionState == ConnectionState.connected) {
      return;
    }

    state = state.copyWith(
      state: LiveKitVoiceState.connecting,
      clearError: true,
    );

    try {
      final token = await _apiService.createToken(
        conversationId: conversationId,
      );
      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = room.createListener();
      _room = room;
      _listener = listener;
      _cancelRoomListener = listener.listen(_handleRoomEvent);

      await room.connect(token.serverUrl, token.token);
      await room.startAudio();
      await room.localParticipant?.setMicrophoneEnabled(true);

      state = state.copyWith(
        state: LiveKitVoiceState.ready,
        microphoneEnabled: true,
        conversationId: token.conversationId,
      );
    } catch (error) {
      await disconnect();
      state = state.copyWith(
        state: LiveKitVoiceState.error,
        error: _messageForError(error),
      );
    }
  }

  Future<void> toggleMicrophone() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;

    try {
      final enabled = !(participant.isMicrophoneEnabled());
      await participant.setMicrophoneEnabled(enabled);
      state = state.copyWith(
        state: enabled ? LiveKitVoiceState.ready : LiveKitVoiceState.muted,
        microphoneEnabled: enabled,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        state: LiveKitVoiceState.error,
        error: _messageForError(error),
      );
    }
  }

  Future<void> disconnect() async {
    await _cancelRoomListener?.call();
    _cancelRoomListener = null;
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
    if (mounted) {
      state = const LiveKitVoiceStateModel();
    }
  }

  void _handleRoomEvent(RoomEvent event) {
    if (event is RoomReconnectingEvent || event is RoomAttemptReconnectEvent) {
      state = state.copyWith(state: LiveKitVoiceState.reconnecting);
      return;
    }
    if (event is RoomReconnectedEvent) {
      state = state.copyWith(
        state: state.microphoneEnabled
            ? LiveKitVoiceState.ready
            : LiveKitVoiceState.muted,
      );
      return;
    }
    if (event is RoomDisconnectedEvent) {
      state = const LiveKitVoiceStateModel();
      return;
    }
    if (event is DataReceivedEvent) {
      _handleData(event.data);
      return;
    }
    if (event is ActiveSpeakersChangedEvent) {
      final agentSpeaking = event.speakers.any(
        (participant) => participant.identity.startsWith('agent'),
      );
      if (agentSpeaking) {
        state = state.copyWith(state: LiveKitVoiceState.speaking);
      } else if (state.microphoneEnabled) {
        state = state.copyWith(state: LiveKitVoiceState.ready);
      }
    }
  }

  void _handleData(List<int> rawData) {
    try {
      final payload = jsonDecode(utf8.decode(rawData));
      if (payload is! Map<String, dynamic>) return;
      final type = payload['type']?.toString();

      if (type == 'transcript') {
        final role = payload['role']?.toString();
        final text = payload['text']?.toString() ?? '';
        state = role == 'user'
            ? state.copyWith(
                userTranscript: text,
                state: LiveKitVoiceState.ready,
              )
            : state.copyWith(assistantTranscript: text);
        return;
      }

      if (type == 'state') {
        final nextState = switch (payload['state']?.toString()) {
          'analyzing' => LiveKitVoiceState.analyzing,
          'speaking' => LiveKitVoiceState.speaking,
          'ready' =>
            state.microphoneEnabled
                ? LiveKitVoiceState.ready
                : LiveKitVoiceState.muted,
          _ => null,
        };
        if (nextState != null) {
          state = state.copyWith(state: nextState);
        }
      }
    } on FormatException {
      state = state.copyWith(
        state: LiveKitVoiceState.error,
        error: 'Nhận dữ liệu LiveKit không hợp lệ.',
      );
    }
  }

  String _messageForError(Object error) {
    final message = error.toString();
    if (message.contains('Permission') || message.contains('permission')) {
      return 'Vui lòng cấp quyền microphone cho TravelWise.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
