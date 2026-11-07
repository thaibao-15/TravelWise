import 'dart:async';

import 'dart:convert';

import 'dart:developer' as developer;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/audio/voice_audio_service.dart';
import '../../../../core/error/exceptions.dart';

import '../../../../core/network/dio_client.dart';

import '../../../auth/auth_di.dart';

import '../../../trips/data/repositories/trip_repository.dart';

import '../../../trips/models/trip_model.dart';

import '../../../trips/providers/trip_provider.dart';
import '../../../livekit/data/services/livekit_api_service.dart';

import '../models/chat_media.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum VoiceState {
  idle,
  listening,
  thinking,
  speaking,
  processing,
  connecting,
  error,
}

enum TripPlanningState {
  idle,

  collectingRequirements,

  readyToGenerate,

  generating,

  previewReady,

  revising,

  readyToSave,

  saving,

  saved,

  error,
}

// ─── Chat Message Model ───────────────────────────────────────────────────────

class ChatMessage {
  final String text;

  final bool isUser;

  final DateTime timestamp;

  final Uint8List? audioBytes;

  final Trip? tripItinerary;

  final List<ChatMedia> media;

  const ChatMessage({
    required this.text,

    required this.isUser,

    required this.timestamp,

    this.audioBytes,

    this.tripItinerary,

    this.media = const [],
  });
}

// ─── State ────────────────────────────────────────────────────────────────────

class VoiceAssistantState {
  final VoiceState voiceState;

  final TripPlanningState planningState;

  final bool isMuted;

  final bool isRecording;

  final bool isConversationExpanded;

  final String currentTranscript;

  final List<ChatMessage> messages;

  final String selectedLanguage;

  final String? error;

  final int? conversationId;

  final bool isTtsEnabled;

  final Uint8List? lastAudioBytes;

  final Trip? tripPreview;

  final String? savedTripId;

  final String? planningContextSummary;

  final Map<String, dynamic>? planningContext;

  final String speakerId;

  final String ttsSpeed;

  const VoiceAssistantState({
    this.voiceState = VoiceState.idle,

    this.planningState = TripPlanningState.idle,

    this.isMuted = false,

    this.isRecording = false,

    this.isConversationExpanded = false,

    this.currentTranscript = '',

    this.messages = const [],

    this.selectedLanguage = 'VN',

    this.error,

    this.conversationId,

    this.isTtsEnabled = true,

    this.lastAudioBytes,

    this.tripPreview,

    this.savedTripId,

    this.planningContextSummary,

    this.planningContext,
    this.speakerId = 'DaNang-Nu-1-BL',
    this.ttsSpeed = '1.5',
  });

  VoiceAssistantState copyWith({
    VoiceState? voiceState,

    TripPlanningState? planningState,

    bool? isMuted,

    bool? isRecording,

    bool? isConversationExpanded,

    String? currentTranscript,

    List<ChatMessage>? messages,

    String? selectedLanguage,

    String? error,

    int? conversationId,
    bool clearConversationId = false,

    bool? isTtsEnabled,

    Uint8List? lastAudioBytes,

    Trip? tripPreview,

    bool clearTripPreview = false,

    String? savedTripId,

    bool clearSavedTripId = false,

    String? planningContextSummary,

    Map<String, dynamic>? planningContext,
    String? speakerId,
    String? ttsSpeed,
  }) {
    return VoiceAssistantState(
      voiceState: voiceState ?? this.voiceState,

      planningState: planningState ?? this.planningState,

      isMuted: isMuted ?? this.isMuted,

      isRecording: isRecording ?? this.isRecording,

      isConversationExpanded:
          isConversationExpanded ?? this.isConversationExpanded,

      currentTranscript: currentTranscript ?? this.currentTranscript,

      messages: messages ?? this.messages,

      selectedLanguage: selectedLanguage ?? this.selectedLanguage,

      error: error,

      conversationId: clearConversationId
          ? null
          : (conversationId ?? this.conversationId),

      isTtsEnabled: isTtsEnabled ?? this.isTtsEnabled,

      lastAudioBytes: lastAudioBytes ?? this.lastAudioBytes,

      tripPreview: clearTripPreview ? null : (tripPreview ?? this.tripPreview),

      savedTripId: clearSavedTripId ? null : (savedTripId ?? this.savedTripId),

      planningContextSummary:
          planningContextSummary ?? this.planningContextSummary,

      planningContext: planningContext ?? this.planningContext,
      speakerId: speakerId ?? this.speakerId,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
    );
  }
}

// ─── Listening configuration ──────────────────────────────────────────────────

/// Client-side voice-activity targets. These are app-level timers layered on

/// top of the recognizer; the platform / STT server may still end a session

/// earlier, which is handled by bounded auto-restart.

class VoiceListeningConfig {
  /// Silence (no new partial/final transcript) required before the utterance
  /// is considered finished and submitted.
  final Duration pauseFor;

  /// Optional shorter silence window used once STT marks a segment as final
  /// (`isFinal == true`), cutting end-of-speech delay without clipping pauses.
  final Duration? finalPauseFor;

  /// Maximum length of one listening turn.

  final Duration listenFor;

  /// Give up if nothing at all is recognised within this window.

  final Duration noSpeechTimeout;

  /// How many times a recognizer that closes unexpectedly may be reopened

  /// within a single listening turn.

  final int maxAutoRestarts;

  const VoiceListeningConfig({
    this.pauseFor = const Duration(milliseconds: 1200),
    this.finalPauseFor,
    this.listenFor = const Duration(seconds: 120),
    this.noSpeechTimeout = const Duration(seconds: 10),
    this.maxAutoRestarts = 2,
  });
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class VoiceAssistantNotifier extends StateNotifier<VoiceAssistantState> {
  final Ref _ref;

  final VoiceAudioService _audioService;

  final VoiceListeningConfig _config;

  static const String _defaultTtsSpeed = '1.5';
  static const String _defaultSpeakerId = 'DaNang-Nu-1-BL';

  void setSpeakerId(String id) {
    if (state.speakerId != id) {
      state = state.copyWith(speakerId: id);
      _publishLiveKitVoiceSettings();
    }
  }

  void setTtsSpeed(String speed) {
    if (state.ttsSpeed != speed) {
      state = state.copyWith(ttsSpeed: speed);
      _publishLiveKitVoiceSettings();
    }
  }

  void _publishLiveKitVoiceSettings() {
    if (!_liveKitAgentAudioReady) return;
    unawaited(_sendLiveKitVoiceSettings());
  }

  Future<void> _sendLiveKitVoiceSettings() async {
    final room = _liveKitRoom;
    final participant = room?.localParticipant;
    if (room?.connectionState != ConnectionState.connected ||
        participant == null ||
        !_liveKitAgentAudioReady) {
      return;
    }

    try {
      await participant.publishData(
        utf8.encode(
          jsonEncode(<String, String>{
            'type': 'command',
            'command': 'set_voice_settings',
            'speaker_id': state.speakerId,
            'speed': state.ttsSpeed,
          }),
        ),
        reliable: true,
      );
      log('livekit_voice_settings_sent', {
        'speakerId': state.speakerId,
        'speed': state.ttsSpeed,
      });
    } catch (error) {
      log('livekit_voice_settings_send_failed', {'error': error.toString()});
      if (mounted) {
        state = state.copyWith(
          error: 'Không thể áp dụng tùy chọn giọng đọc cho trợ lý thoại.',
        );
      }
    }
  }

  Future<void> previewVoiceSample(
    String speakerId, {
    String? speed,
    String? sampleText,
  }) async {
    final text =
        sampleText ?? 'Xin chào bạn! Mình là trợ lý du lịch AI TravelWise.';
    final spd = speed ?? state.ttsSpeed;
    _audioService.stopTts();
    _audioService.initStreamingQueue(
      onPlay: () {
        if (mounted) {
          state = state.copyWith(voiceState: VoiceState.speaking);
        }
      },
      onEnded: () {
        if (mounted) {
          state = state.copyWith(voiceState: VoiceState.idle);
        }
      },
      onError: (err) {
        if (mounted) {
          state = state.copyWith(voiceState: VoiceState.idle);
        }
      },
    );
    _audioService.enqueueSentence(
      baseUrl: ApiConfig.baseUrl,
      sentence: text,
      speed: spd,
      speakerId: speakerId,
    );
    _audioService.markStreamDone();
  }

  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  Timer? _maxSessionTimer;
  Timer? _ttsSafetyTimer;
  Timer? _resumeListenTimer;
  Timer? _dedupeResetTimer;
  String? _lastSubmittedTranscript;
  bool _isCommitting = false;
  int _requestGeneration = 0;

  /// Uses browser Fetch ReadableStream on Web so SSE tokens arrive immediately
  /// without XMLHttpRequest full-response buffering. Overridable in tests.
  bool get useNativeFetchStream => kIsWeb;

  /// Real-time 60fps audio lip-sync stream for the Linh AI portrait.
  ValueListenable<LipSyncFrame> get lipSyncListenable =>
      _audioService.lipSyncListenable;

  /// Id of the current recognizer connection; stale callbacks are dropped.

  int _sessionId = 0;

  /// True while the user wants the mic open (spans recognizer restarts).

  bool _listeningTurnActive = false;

  int _autoRestarts = 0;

  DateTime? _turnStartedAt;

  /// Finalised transcript segments of the current turn + the live partial.

  final List<String> _finalSegments = [];

  String _partialSegment = '';

  bool _hasGreeted = false;

  /// Flag indicating if TTS playback has been stopped/cancelled by the user.

  bool _ttsCancelled = false;

  bool _isVoiceSession = false;
  bool _userKeepMicOn = false;
  final bool _useLiveKitVoice = true;
  Room? _liveKitRoom;
  EventsListener<RoomEvent>? _liveKitListener;
  CancelListenFunc? _cancelLiveKitListener;
  bool _liveKitConnecting = false;
  Completer<void>? _liveKitConnectCompleter;
  bool _liveKitClosing = false;
  Future<void>? _liveKitCloseFuture;
  bool _liveKitAgentAudioReady = false;
  bool _liveKitNeedsFreshRoom = false;
  Completer<void>? _liveKitAgentReady;
  String _lastLiveKitUserTranscript = '';
  List<ChatMedia> _liveKitPendingMedia = const [];

  bool _isDirectTripEditMode = false;
  Trip? _directEditTrip;
  int? _directEditTargetDay;

  bool get isDirectTripEditMode => _isDirectTripEditMode;

  void _resumeListeningIfPersistent() {
    if (!mounted) return;
    if ((_userKeepMicOn || _isVoiceSession) && !state.isMuted) {
      log('hands_free_auto_listen_triggered');
      state = state.copyWith(voiceState: VoiceState.idle, error: null);
      _resumeListenTimer?.cancel();
      _resumeListenTimer = Timer(const Duration(milliseconds: 180), () {
        if (mounted &&
            !state.isRecording &&
            !state.isMuted &&
            (_userKeepMicOn || _isVoiceSession)) {
          _beginListening();
        }
      });
    } else {
      state = state.copyWith(voiceState: VoiceState.idle);
    }
  }

  VoiceAssistantNotifier(
    this._ref, {
    VoiceAudioService? audioService,
    VoiceListeningConfig config = const VoiceListeningConfig(
      pauseFor: Duration(milliseconds: 900),
      finalPauseFor: Duration(milliseconds: 400),
    ),
  }) : _audioService = audioService ?? VoiceAudioService(),

       _config = config,

       super(const VoiceAssistantState());

  Dio get _dio => _ref.read(dioClientProvider).dio;

  TripRepository get _tripRepo => _ref.read(tripRepositoryProvider);

  void log(String event, [Map<String, Object?>? detail]) {
    final payload = detail == null ? event : '$event $detail';

    developer.log('[VoiceAI] $payload', name: 'VoiceAI');

    // ignore: avoid_print
    print('[VoiceAI] $payload');
  }

  // ── Simple state setters ──────────────────────────────────────────────────

  void setVoiceState(VoiceState vs) {
    log('setVoiceState', {'voiceState': vs.name});

    state = state.copyWith(voiceState: vs);
  }

  void setPlanningState(TripPlanningState ps) {
    log('setPlanningState', {'planningState': ps.name});

    state = state.copyWith(planningState: ps);
  }

  void setTranscript(String text) {
    state = state.copyWith(currentTranscript: text);
  }

  void toggleConversation() {
    state = state.copyWith(
      isConversationExpanded: !state.isConversationExpanded,
    );
  }

  void toggleLanguage() {
    final next = state.selectedLanguage == 'VN' ? 'EN' : 'VN';

    state = state.copyWith(selectedLanguage: next);
  }

  void toggleTts() {
    log('toggleTts', {'enabled': !state.isTtsEnabled});

    state = state.copyWith(isTtsEnabled: !state.isTtsEnabled);
  }

  void toggleMute() {
    if (_useLiveKitVoice) {
      if (state.isMuted) {
        unawaited(_enableLiveKitMicrophone());
      } else {
        unawaited(_disableLiveKitMicrophone());
      }
      return;
    }
    if (state.isMuted) {
      log('mic_unmuted');

      state = state.copyWith(isMuted: false);
    } else {
      log('mic_muted');

      _abortListening();

      _audioService.stopTts();

      state = state.copyWith(
        isMuted: true,

        isRecording: false,

        voiceState: VoiceState.idle,
      );
    }
  }

  /// Barge-in: interrupt AI stream/speech immediately and open the mic for user turn.
  void bargeIn() {
    if (_useLiveKitVoice) {
      log('livekit_stop_speaking');
      unawaited(stopLiveKitSpeaking());
      return;
    }
    log('barge_in_triggered');
    _requestGeneration++;
    _isCommitting = false;
    _audioService.abortStream();
    stopAudio();
    _userKeepMicOn = true;
    _isVoiceSession = true;
    state = state.copyWith(voiceState: VoiceState.idle, error: null);
    _resumeListenTimer?.cancel();
    _resumeListenTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted && !state.isMuted) {
        _beginListening();
      }
    });
  }

  void toggleRecording() {
    if (_useLiveKitVoice) {
      unawaited(_toggleLiveKitVoice());
      return;
    }

    if (state.voiceState == VoiceState.speaking ||
        state.voiceState == VoiceState.thinking ||
        state.voiceState == VoiceState.processing) {
      log('user_toggle_recording_barge_in');
      bargeIn();
      return;
    }

    if (_listeningTurnActive ||
        state.isRecording ||
        state.voiceState == VoiceState.connecting ||
        state.voiceState == VoiceState.listening) {
      log('user_toggle_recording_off');
      _userKeepMicOn = false;
      _isVoiceSession = false;
      _finishListening(reason: 'manual_stop', submit: true);
    } else {
      if (state.isMuted) {
        log('record_blocked_muted');
        return;
      }
      if (_isCommitting ||
          state.voiceState == VoiceState.thinking ||
          state.voiceState == VoiceState.processing) {
        log('record_blocked_busy', {'voiceState': state.voiceState.name});
        return;
      }
      log('user_toggle_recording_on');
      _isDirectTripEditMode = false;
      _directEditTrip = null;
      _directEditTargetDay = null;
      _userKeepMicOn = true;
      _isVoiceSession = true;
      _beginListening();
    }
  }

  Future<void> startLiveKitVoice() async {
    if (!_useLiveKitVoice) return;

    _isVoiceSession = true;
    final connecting = _liveKitConnectCompleter;
    if (connecting != null) {
      final timer = Stopwatch()..start();
      await connecting.future;
      log('livekit_connect_in_progress_waited', {
        'durationMs': timer.elapsedMilliseconds,
      });
      if (!mounted || !_isVoiceSession) return;
    }

    final closing = _liveKitCloseFuture;
    if (closing != null) {
      final timer = Stopwatch()..start();
      await closing;
      log('livekit_previous_room_close_waited', {
        'durationMs': timer.elapsedMilliseconds,
      });
      if (!mounted || !_isVoiceSession || _liveKitConnecting) return;
    }

    if (_liveKitNeedsFreshRoom) {
      await _connectLiveKitVoice();
      return;
    }

    final room = _liveKitRoom;
    if (room?.connectionState == ConnectionState.connected) {
      final participant = room?.localParticipant;
      if (participant != null && !participant.isMicrophoneEnabled()) {
        await _enableLiveKitMicrophone();
      }
      return;
    }

    await _connectLiveKitVoice();
  }

  Future<void> _toggleLiveKitVoice() async {
    if (_liveKitConnecting) return;
    _isVoiceSession = true;
    if (_liveKitNeedsFreshRoom) {
      await _disconnectLiveKit(clearConversation: false);
      await _connectLiveKitVoice();
      return;
    }

    if (_liveKitRoom?.connectionState == ConnectionState.connected) {
      final participant = _liveKitRoom!.localParticipant;
      if (participant == null) return;
      final enabled = participant.isMicrophoneEnabled();
      if (!enabled || state.isMuted) {
        await _enableLiveKitMicrophone();
      } else if (state.voiceState == VoiceState.speaking) {
        await _enableLiveKitMicrophone();
      } else {
        await _disableLiveKitMicrophone();
      }
      return;
    }

    await _connectLiveKitVoice();
  }

  Future<void> _connectLiveKitVoice() async {
    if (_liveKitConnecting) return;
    final closing = _liveKitCloseFuture;
    if (closing != null) {
      await closing;
      if (!mounted || !_isVoiceSession || _liveKitConnecting) return;
    }
    if (_liveKitRoom != null) {
      await _disconnectLiveKit(clearConversation: false);
      if (!mounted || !_isVoiceSession || _liveKitConnecting) return;
    }
    _liveKitConnecting = true;
    final connectCompleter = Completer<void>();
    _liveKitConnectCompleter = connectCompleter;
    final connectTimer = Stopwatch()..start();
    state = state.copyWith(
      voiceState: VoiceState.connecting,
      error: null,
      isRecording: false,
    );

    try {
      final tokenTimer = Stopwatch()..start();
      final token = await LiveKitApiService(_ref.read(dioClientProvider))
          .createToken(
            conversationId: state.conversationId,
            roomName: _liveKitNeedsFreshRoom
                ? 'travelwise_conv_${state.conversationId ?? 'new'}_session_${DateTime.now().microsecondsSinceEpoch}'
                : null,
          );
      log('livekit_token_ready', {
        'durationMs': tokenTimer.elapsedMilliseconds,
      });
      if (!mounted || !_isVoiceSession) return;

      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = room.createListener();
      _liveKitRoom = room;
      _liveKitListener = listener;
      _liveKitAgentAudioReady = false;
      _liveKitAgentReady = Completer<void>();
      _cancelLiveKitListener = listener.listen(_handleLiveKitEvent);
      final roomTimer = Stopwatch()..start();
      await room.connect(token.serverUrl, token.token);
      log('livekit_room_connected', {
        'durationMs': roomTimer.elapsedMilliseconds,
      });
      if (!mounted || !_isVoiceSession) {
        await _disconnectLiveKit(clearConversation: false);
        return;
      }

      final audioTimer = Stopwatch()..start();
      await room.startAudio();
      if (!mounted || !_isVoiceSession) {
        await _disconnectLiveKit(clearConversation: false);
        return;
      }

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('LiveKit room connected without a local participant.');
      }
      await localParticipant.setMicrophoneEnabled(true);
      if (!mounted || !_isVoiceSession) {
        await _disconnectLiveKit(clearConversation: false);
        return;
      }

      log('livekit_microphone_ready', {
        'durationMs': audioTimer.elapsedMilliseconds,
        'totalDurationMs': connectTimer.elapsedMilliseconds,
      });
      state = state.copyWith(
        conversationId: token.conversationId,
        voiceState: VoiceState.listening,
        isRecording: true,
        isMuted: false,
        error: null,
      );
      unawaited(
        _waitForLiveKitAgent(room)
            .then((_) {
              if (mounted &&
                  identical(_liveKitRoom, room) &&
                  room.connectionState == ConnectionState.connected) {
                _liveKitNeedsFreshRoom = false;
              }
              log('livekit_agent_ready');
            })
            .catchError((Object error) {
              log('livekit_agent_wait_failed', {'error': error.toString()});
              if (mounted &&
                  identical(_liveKitRoom, room) &&
                  room.connectionState == ConnectionState.connected) {
                unawaited(
                  _markLiveKitUnavailable(
                    'Đã kết nối microphone nhưng trợ lý chưa sẵn sàng. Vui lòng thử lại sau ít phút.',
                  ),
                );
              }
            }),
      );
    } catch (error) {
      await _disconnectLiveKit(clearConversation: false);
      if (mounted && _isVoiceSession) {
        state = state.copyWith(
          voiceState: VoiceState.error,
          isRecording: false,
          error: _messageForLiveKitError(error),
        );
      }
    } finally {
      _liveKitConnecting = false;
      if (identical(_liveKitConnectCompleter, connectCompleter)) {
        _liveKitConnectCompleter = null;
      }
      if (!connectCompleter.isCompleted) connectCompleter.complete();
    }
  }

  Future<void> _waitForLiveKitAgent(Room room) async {
    const timeout = Duration(seconds: 20);
    const pollInterval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final agentConnected = room.remoteParticipants.values.any(
        _isLiveKitAgent,
      );
      if (agentConnected) return;

      final remaining = deadline.difference(DateTime.now());
      final waitDuration = remaining < pollInterval ? remaining : pollInterval;
      final agentReady = _liveKitAgentReady;
      if (agentReady != null && !agentReady.isCompleted) {
        await Future.any<void>(<Future<void>>[
          agentReady.future,
          Future<void>.delayed(waitDuration),
        ]);
      } else {
        await Future<void>.delayed(waitDuration);
      }
    }

    throw StateError(
      'Hiện chưa thể kết nối trợ lý giọng nói. Vui lòng thử lại sau ít phút.',
    );
  }

  bool _isLiveKitAgent(RemoteParticipant participant) {
    final identity = participant.identity.toLowerCase();
    return participant.kind == ParticipantKind.AGENT ||
        identity.startsWith('agent-');
  }

  Future<void> _enableLiveKitMicrophone() async {
    final participant = _liveKitRoom?.localParticipant;
    if (participant == null) return;
    await participant.setMicrophoneEnabled(true);
    state = state.copyWith(
      voiceState: VoiceState.listening,
      isRecording: true,
      isMuted: false,
      error: null,
    );
  }

  Future<void> _disableLiveKitMicrophone() async {
    final participant = _liveKitRoom?.localParticipant;
    if (participant == null) return;
    await participant.setMicrophoneEnabled(false);
    state = state.copyWith(
      voiceState: VoiceState.idle,
      isRecording: false,
      isMuted: true,
    );
  }

  Future<void> stopLiveKitSpeaking() async {
    final room = _liveKitRoom;
    if (room == null ||
        room.connectionState != ConnectionState.connected ||
        room.localParticipant == null) {
      return;
    }

    try {
      await room.localParticipant!.publishData(
        utf8.encode(
          jsonEncode(<String, String>{
            'type': 'command',
            'command': 'stop_speaking',
          }),
        ),
        reliable: true,
      );
      await _enableLiveKitMicrophone();
    } catch (error) {
      state = state.copyWith(
        voiceState: VoiceState.error,
        error: _messageForLiveKitError(error),
      );
    }
  }

  void _handleLiveKitEvent(RoomEvent event) {
    if (event is RoomReconnectingEvent || event is RoomAttemptReconnectEvent) {
      state = state.copyWith(voiceState: VoiceState.connecting);
      return;
    }
    if (event is RoomReconnectedEvent) {
      state = state.copyWith(
        voiceState: state.isMuted ? VoiceState.idle : VoiceState.listening,
      );
      return;
    }
    if (event is RoomDisconnectedEvent) {
      if (_liveKitClosing) return;
      unawaited(_handleUnexpectedLiveKitDisconnect());
      return;
    }
    if (event is ParticipantConnectedEvent) {
      log('livekit_participant_connected', {
        'identity': event.participant.identity,
        'kind': event.participant.kind.name,
      });
      if (_isLiveKitAgent(event.participant) &&
          _liveKitAgentReady != null &&
          !_liveKitAgentReady!.isCompleted) {
        _liveKitNeedsFreshRoom = false;
        _liveKitAgentReady!.complete();
      }
      return;
    }
    if (event is ParticipantDisconnectedEvent &&
        _isLiveKitAgent(event.participant)) {
      unawaited(
        _markLiveKitUnavailable(
          'Trợ lý giọng nói đã ngắt kết nối. Chạm micro để kết nối lại.',
        ),
      );
      log('livekit_agent_disconnected', {
        'identity': event.participant.identity,
      });
      return;
    }
    if (event is TrackSubscribedEvent &&
        _isLiveKitAgent(event.participant) &&
        event.track.kind == TrackType.AUDIO) {
      _liveKitAgentAudioReady = true;
      log('livekit_agent_audio_subscribed');
      unawaited(_sendLiveKitVoiceSettings());
      return;
    }
    if (event is DataReceivedEvent) {
      _handleLiveKitData(event.data);
    }
  }

  void _handleLiveKitData(List<int> rawData) {
    try {
      final payload = jsonDecode(utf8.decode(rawData));
      if (payload is! Map<String, dynamic>) return;
      final type = payload['type']?.toString();
      if (type == 'conversation') {
        final id = payload['conversation_id'];
        state = state.copyWith(
          conversationId: id is num ? id.toInt() : int.tryParse('$id'),
        );
        return;
      }
      if (type == 'transcript') {
        final role = payload['role']?.toString();
        final text = payload['text']?.toString() ?? '';
        final isFinal = payload['is_final'] == true;
        if (role == 'user') {
          state = state.copyWith(
            currentTranscript: text,
            voiceState: isFinal ? VoiceState.thinking : VoiceState.listening,
            isRecording: !isFinal,
          );
          if (isFinal) {
            _lastLiveKitUserTranscript = text;
            _upsertLiveKitUserMessage(text);
          }
        } else if (role == 'assistant') {
          state = state.copyWith(
            currentTranscript: text,
            voiceState: isFinal ? VoiceState.idle : VoiceState.speaking,
          );
          _upsertLiveKitAssistantMessage(text, isFinal);
        }
        return;
      }
      if (type == 'metadata') {
        _applyLiveKitMetadata(payload);
        return;
      }
      if (type == 'state') {
        final next = switch (payload['state']?.toString()) {
          'analyzing' => VoiceState.thinking,
          'speaking' => VoiceState.speaking,
          'ready' || 'listening' => VoiceState.listening,
          'error' => VoiceState.error,
          _ => null,
        };
        if (next != null) {
          if (next == VoiceState.error) {
            unawaited(
              _markLiveKitUnavailable(
                payload['error']?.toString() ??
                    'Trợ lý thoại đã gặp lỗi. Chạm micro để kết nối lại.',
              ),
            );
            return;
          }
          state = state.copyWith(
            voiceState: next,
            error: payload['error']?.toString(),
          );
        }
        return;
      }
      if (type == 'voice_settings') {
        if (payload['status'] == 'applied') {
          log('livekit_voice_settings_applied', {
            'speakerId': payload['speaker_id'],
            'speed': payload['speed'],
          });
        } else {
          log('livekit_voice_settings_rejected');
          state = state.copyWith(
            error: 'Không thể áp dụng tùy chọn giọng đọc cho trợ lý thoại.',
          );
        }
        return;
      }
      if (type == 'error') {
        unawaited(
          _markLiveKitUnavailable(
            payload['message']?.toString() ?? 'LiveKit voice error.',
          ),
        );
      }
    } on FormatException catch (error) {
      log('livekit_invalid_data', {'error': error.toString()});
      state = state.copyWith(
        voiceState: VoiceState.error,
        error: 'Dữ liệu voice realtime không hợp lệ.',
      );
    }
  }

  void _upsertLiveKitAssistantMessage(String text, bool isFinal) {
    if (text.trim().isEmpty) return;
    final messages = [...state.messages];
    if (messages.isNotEmpty && !messages.last.isUser) {
      messages[messages.length - 1] = ChatMessage(
        text: text,
        isUser: false,
        timestamp: messages.last.timestamp,
        media: isFinal ? _liveKitPendingMedia : messages.last.media,
      );
    } else if (isFinal || messages.isEmpty) {
      messages.add(
        ChatMessage(
          text: text,
          isUser: false,
          timestamp: DateTime.now(),
          media: _liveKitPendingMedia,
        ),
      );
      _liveKitPendingMedia = const [];
    }
    state = state.copyWith(messages: messages);
  }

  void _upsertLiveKitUserMessage(String text) {
    if (text.trim().isEmpty) return;
    final messages = [...state.messages];
    if (messages.isNotEmpty &&
        messages.last.isUser &&
        messages.last.text == text) {
      return;
    }
    messages.add(
      ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
    );
    state = state.copyWith(messages: messages);
  }

  void _applyLiveKitMetadata(Map<String, dynamic> payload) {
    final rawContext = payload['planning_context'];
    final context = rawContext is Map
        ? Map<String, dynamic>.from(rawContext)
        : null;
    final action = payload['planning_action']?.toString();
    final rawMedia = payload['media'];
    if (rawMedia is List) {
      _liveKitPendingMedia = rawMedia
          .whereType<Map>()
          .map((item) => ChatMedia.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    final isReady = payload['is_ready_to_generate'] == true;
    final status = payload['planning_status']?.toString();
    final planningState = status == 'collecting_requirements'
        ? TripPlanningState.collectingRequirements
        : (isReady ? TripPlanningState.readyToGenerate : state.planningState);
    state = state.copyWith(
      conversationId: _parseConversationId(payload['conversation_id']),
      planningContext: context,
      planningContextSummary: context == null
          ? state.planningContextSummary
          : _formatPlanningContextSummary(context),
      planningState: planningState,
    );
    if (action == 'TRIGGER_GENERATION' && state.conversationId != null) {
      unawaited(
        generateItinerary(
          convId: state.conversationId!,
          context: context,
          userPrompt: _lastLiveKitUserTranscript,
        ),
      );
    } else if (action == 'TRIGGER_EDIT') {
      final targetTripId =
          state.savedTripId ??
          (state.tripPreview?.id != null &&
                  state.tripPreview!.id.isNotEmpty &&
                  state.tripPreview!.id != '0'
              ? state.tripPreview!.id.toString()
              : _activeTripIdFromState(context));

      final editPrompt = _lastLiveKitUserTranscript.trim();
      if (editPrompt.isNotEmpty &&
          (state.tripPreview != null || targetTripId != null)) {
        log('livekit_trigger_edit', {
          'targetTripId': targetTripId,
          'prompt': editPrompt,
        });
        unawaited(editCurrentOrSavedTrip(instruction: editPrompt));
      }
    } else if (action == 'TRIGGER_SAVE' && state.conversationId != null) {
      unawaited(saveCurrentTrip(convId: state.conversationId));
    }
  }

  String _messageForLiveKitError(Object error) {
    final message = error.toString();
    if (message.contains('Hiện chưa thể kết nối trợ lý giọng nói')) {
      return 'Hiện chưa thể kết nối trợ lý giọng nói. Vui lòng thử lại sau ít phút.';
    }
    if (message.toLowerCase().contains('permission')) {
      return 'Vui lòng cấp quyền microphone cho TravelWise.';
    }
    return 'Không thể kết nối trợ lý giọng nói. Vui lòng kiểm tra mạng và thử lại.';
  }

  int? _parseConversationId(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> disconnectLiveKitVoice() async {
    _isVoiceSession = false;
    await _disconnectLiveKitAfterPendingConnect(clearConversation: true);
  }

  Future<void> leaveLiveKitVoice() async {
    _isVoiceSession = false;
    _liveKitNeedsFreshRoom = true;
    await _disconnectLiveKitAfterPendingConnect(
      clearConversation: false,
      onlyIfSessionEnded: true,
    );
  }

  Future<void> _disconnectLiveKitAfterPendingConnect({
    required bool clearConversation,
    bool onlyIfSessionEnded = false,
  }) async {
    final connecting = _liveKitConnectCompleter;
    if (connecting != null) await connecting.future;
    if (onlyIfSessionEnded && _isVoiceSession) return;
    await _disconnectLiveKit(clearConversation: clearConversation);
  }

  Future<void> _handleUnexpectedLiveKitDisconnect() async {
    await _disconnectLiveKit(clearConversation: false);
    await _markLiveKitUnavailable(
      'Kết nối phòng thoại bị gián đoạn. Chạm micro để thử lại.',
    );
  }

  Future<void> _markLiveKitUnavailable(String message) async {
    _liveKitNeedsFreshRoom = true;
    if (mounted) {
      state = state.copyWith(
        voiceState: VoiceState.error,
        isRecording: false,
        error: message,
      );
    }

    final participant = _liveKitRoom?.localParticipant;
    if (participant != null && participant.isMicrophoneEnabled()) {
      try {
        await participant.setMicrophoneEnabled(false);
      } catch (error) {
        log('livekit_mic_stop_failed', {'error': error.toString()});
      }
    }
  }

  Future<void> _disconnectLiveKit({required bool clearConversation}) {
    final closing = _liveKitCloseFuture;
    if (closing != null) return closing;
    late final Future<void> closeFuture;
    closeFuture =
        _performLiveKitDisconnect(
          clearConversation: clearConversation,
        ).whenComplete(() {
          if (identical(_liveKitCloseFuture, closeFuture)) {
            _liveKitCloseFuture = null;
          }
        });
    _liveKitCloseFuture = closeFuture;
    return closeFuture;
  }

  Future<void> _performLiveKitDisconnect({
    required bool clearConversation,
  }) async {
    if (_liveKitClosing) return;
    _liveKitClosing = true;
    final cancelListener = _cancelLiveKitListener;
    final listener = _liveKitListener;
    final room = _liveKitRoom;
    _cancelLiveKitListener = null;
    _liveKitListener = null;
    _liveKitRoom = null;
    _liveKitAgentAudioReady = false;
    _liveKitAgentReady = null;
    try {
      await cancelListener?.call();
      listener?.dispose();
      if (room != null) {
        await room.localParticipant?.setMicrophoneEnabled(false);
        await room.disconnect();
        await room.dispose();
      }
    } finally {
      _liveKitClosing = false;
    }
    if (mounted) {
      _lastLiveKitUserTranscript = '';
      _liveKitPendingMedia = const [];
      state = state.copyWith(
        voiceState: VoiceState.idle,
        isRecording: false,
        isMuted: false,
        clearConversationId: clearConversation,
      );
    }
  }

  /// Bật / tắt chế độ nói trực tiếp để chỉnh sửa lịch trình ngay tại màn hình Chi tiết chuyến đi
  /// mà không cần chuyển sang tab Trợ lý AI.
  void toggleDirectTripVoiceEdit({required Trip trip, int? targetDay}) {
    if (state.voiceState == VoiceState.speaking) {
      log('direct_trip_voice_stop_tts');
      stopAudio();
      return;
    }

    if (_listeningTurnActive ||
        state.isRecording ||
        state.voiceState == VoiceState.connecting ||
        state.voiceState == VoiceState.listening) {
      log('direct_trip_voice_manual_submit');
      _userKeepMicOn = false;
      _isVoiceSession = false;
      _finishListening(reason: 'direct_trip_manual_stop', submit: true);
      return;
    }

    if (_isCommitting ||
        state.planningState == TripPlanningState.revising ||
        state.voiceState == VoiceState.thinking ||
        state.voiceState == VoiceState.processing) {
      log('direct_trip_voice_blocked_busy', {
        'voiceState': state.voiceState.name,
      });
      return;
    }

    if (state.isMuted) {
      state = state.copyWith(isMuted: false);
    }

    log('direct_trip_voice_start', {'tripId': trip.id, 'targetDay': targetDay});
    _isDirectTripEditMode = true;
    _directEditTrip = trip;
    _directEditTargetDay = targetDay;
    _userKeepMicOn = false;
    _isVoiceSession = false;

    final hasPersistedId = _isValidPersistedTripId(trip.id);
    state = state.copyWith(
      tripPreview: trip,
      savedTripId: hasPersistedId ? trip.id.trim() : null,
      clearSavedTripId: !hasPersistedId,
      planningState: (hasPersistedId && trip.status == 'CONFIRMED')
          ? TripPlanningState.saved
          : TripPlanningState.previewReady,
      error: null,
    );

    _beginDirectTripListening();
  }

  /// Huỷ phiên thu âm chỉnh sửa trực tiếp tại trang chi tiết chuyến đi mà không gửi yêu cầu.
  void cancelDirectTripVoiceEdit() {
    log('direct_trip_voice_cancel');
    _isDirectTripEditMode = false;
    _directEditTrip = null;
    _directEditTargetDay = null;
    _userKeepMicOn = false;
    _isVoiceSession = false;
    _abortListening();
    state = state.copyWith(
      isRecording: false,
      voiceState: VoiceState.idle,
      currentTranscript: '',
      error: null,
    );
  }

  /// Dừng an toàn micro / giọng đọc đang chạy trên màn hình Chi tiết chuyến đi (ví dụ khi thoát trang).
  void stopDirectTripVoiceSession({bool fromDispose = false}) {
    final hadActiveVoice =
        _isDirectTripEditMode ||
        _listeningTurnActive ||
        state.isRecording ||
        state.voiceState == VoiceState.speaking ||
        state.voiceState == VoiceState.listening ||
        state.voiceState == VoiceState.connecting;

    _isDirectTripEditMode = false;
    _directEditTrip = null;
    _directEditTargetDay = null;
    if (!hadActiveVoice) return;

    _userKeepMicOn = false;
    _isVoiceSession = false;
    _abortListening();
    _ttsCancelled = true;
    _audioService.stopTts();

    void resetIdleState() {
      if (mounted &&
          state.planningState != TripPlanningState.revising &&
          state.planningState != TripPlanningState.generating) {
        state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
      }
    }

    if (fromDispose) {
      Future.microtask(resetIdleState);
    } else {
      resetIdleState();
    }
  }

  void stopSpeaking() => stopAudio();

  void stopAudio() {
    log('tts_stop');
    _ttsCancelled = true;
    _ttsSafetyTimer?.cancel();
    _audioService.stopTts();

    if (state.voiceState == VoiceState.speaking) {
      state = state.copyWith(voiceState: VoiceState.idle);
    }
  }

  void dismissPreview() {
    state = state.copyWith(
      planningState: TripPlanningState.idle,

      clearTripPreview: true,
    );
  }

  /// Clears the chat conversation history and planning state.
  void clearConversation() {
    log('chat_clear_conversation');
    _requestGeneration++;
    _isCommitting = false;
    _isVoiceSession = false;
    _audioService.abortStream();
    stopAudio();
    _abortListening();
    unawaited(
      _disconnectLiveKitAfterPendingConnect(
        clearConversation: true,
        onlyIfSessionEnded: true,
      ),
    );

    state = state.copyWith(
      messages: [],
      clearConversationId: true,
      currentTranscript: '',
      planningState: TripPlanningState.idle,
      clearTripPreview: true,
      planningContext: null,
      planningContextSummary: null,
      voiceState: VoiceState.idle,
      isRecording: false,
    );
  }

  /// Load messages from an existing conversation and set it as active.
  Future<void> loadConversation(int conversationId) async {
    log('load_conversation_by_id', {'conversationId': conversationId});
    _audioService.abortStream();
    stopAudio();
    _abortListening();

    try {
      final response = await _dio.get('/api/v1/conversations/$conversationId/messages');
      if (response.statusCode == 200 && response.data is List) {
        final rawMessages = response.data as List;
        final loadedMessages = <ChatMessage>[];

        for (final item in rawMessages) {
          if (item is Map<String, dynamic>) {
            final sender = item['sender']?.toString().toUpperCase() ?? '';
            final content = item['content']?.toString() ?? '';
            final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now();

            loadedMessages.add(
              ChatMessage(
                text: content,
                isUser: sender == 'USER',
                timestamp: createdAt,
              ),
            );
          }
        }

        state = state.copyWith(
          conversationId: conversationId,
          messages: loadedMessages,
          currentTranscript: '',
          voiceState: VoiceState.idle,
          isRecording: false,
        );
      }
    } catch (e) {
      log('load_conversation_failed: $e');
    }
  }

  /// AI tự động chào và giới thiệu với người dùng khi mở màn hình Trợ lý du lịch.

  Future<void> greetUser({String? userName}) async {
    if (_hasGreeted || state.messages.isNotEmpty) return;

    _hasGreeted = true;

    final displayName = (userName != null && userName.trim().isNotEmpty)
        ? userName.trim()
        : 'bạn';

    final greetingText =
        'Xin chào $displayName! Mình là Linh AI - trợ lý du lịch đồng hành cùng bạn tại TravelWise. Hôm nay bạn muốn lên lịch trình hay khám phá điểm đến nào?';

    log('ai_greeting_user', {'displayName': displayName});

    final greetingMsg = ChatMessage(
      text: greetingText,

      isUser: false,

      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [greetingMsg],

      currentTranscript: greetingText,
    );

    if (state.isTtsEnabled && !_useLiveKitVoice) {
      await _playTts(greetingText);
    }
  }

  /// Khởi tạo lại cuộc trò chuyện và chào lại nếu cần.

  void resetConversation({String? userName}) {
    _requestGeneration++;
    _isCommitting = false;
    _audioService.abortStream();
    _abortListening();
    stopAudio();

    _hasGreeted = false;

    state = const VoiceAssistantState();

    greetUser(userName: userName);
  }

  /// Cancels an active listening turn without submitting (e.g. user left the

  /// assistant tab).

  void cancelListening() {
    if (_useLiveKitVoice) {
      unawaited(_disableLiveKitMicrophone());
      return;
    }

    _userKeepMicOn = false;
    _isVoiceSession = false;
    if (!_listeningTurnActive && !state.isRecording) return;

    log('stt_cancel');

    _abortListening();

    state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
  }

  /// Must run before any TTS playback so the AI never hears itself.

  void prepareForTtsPlayback() {
    _ttsCancelled = false;
    _ttsSafetyTimer?.cancel();

    if (_listeningTurnActive || state.isRecording) {
      log('stt_suspended_for_tts');

      _abortListening();

      state = state.copyWith(isRecording: false);
    }
  }

  // ── STT (Web Microphone WebSocket) ───────────────────────────────────────

  String get _accumulatedTranscript => [
    ..._finalSegments,

    if (_partialSegment.isNotEmpty) _partialSegment,
  ].join(' ').trim();

  bool _isActiveSession(int sessionId) =>
      mounted && _listeningTurnActive && sessionId == _sessionId;

  void _beginListening() {
    if (_listeningTurnActive) return;

    _cancelTimers();

    _finalSegments.clear();

    _partialSegment = '';

    _isCommitting = false;

    _autoRestarts = 0;

    _turnStartedAt = DateTime.now();

    _audioService.unlockAudio();

    _listeningTurnActive = true;

    _isVoiceSession = true;

    _audioService.stopTts();

    state = state.copyWith(
      voiceState: VoiceState.connecting,

      currentTranscript: '',

      error: null,

      isRecording: false,
    );

    _maxSessionTimer = Timer(_config.listenFor, () {
      if (!mounted || !_listeningTurnActive) return;

      log('stt_max_session_reached');

      _finishListening(reason: 'max_session', submit: true);
    });

    _openRecognizer();
  }

  void _beginDirectTripListening() {
    if (_listeningTurnActive) return;

    _cancelTimers();
    _finalSegments.clear();
    _partialSegment = '';
    _isCommitting = false;
    _autoRestarts = 0;
    _turnStartedAt = DateTime.now();
    _audioService.unlockAudio();
    _listeningTurnActive = true;
    _isVoiceSession = false;
    _userKeepMicOn = false;
    _audioService.stopTts();

    state = state.copyWith(
      voiceState: VoiceState.connecting,
      currentTranscript: '',
      error: null,
      isRecording: false,
    );

    _maxSessionTimer = Timer(_config.listenFor, () {
      if (!mounted || !_listeningTurnActive) return;
      log('stt_max_session_reached_direct_trip');
      _finishListening(reason: 'max_session', submit: true);
    });

    _openRecognizer();
  }

  void _openRecognizer() {
    final sessionId = ++_sessionId;

    final baseUrl = ApiConfig.baseUrl;

    final wsProtocol = baseUrl.startsWith('https') ? 'wss:' : 'ws:';

    final wsHost = baseUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');

    final wsUrl = '$wsProtocol//$wsHost/api/v1/stt/ws';

    log('stt_start', {
      'wsUrl': wsUrl,

      'sessionId': sessionId,

      'autoRestarts': _autoRestarts,
    });

    _audioService.startRecording(
      wsUrl: wsUrl,

      onReady: () {
        if (!_isActiveSession(sessionId)) return;

        log('stt_ready', {'sessionId': sessionId});

        state = state.copyWith(
          voiceState: VoiceState.listening,

          isRecording: true,

          error: null,
        );

        if (_accumulatedTranscript.isEmpty) _armNoSpeechTimer(sessionId);
      },

      onTranscript: (text, isFinal) {
        if (!_isActiveSession(sessionId)) return;

        log('stt_transcript', {
          'isFinal': isFinal,

          'textLength': text.length,

          'sessionId': sessionId,
        });

        _handleTranscript(text, isFinal);
      },

      onError: (err) {
        if (!_isActiveSession(sessionId)) return;

        log('stt_error', {'error': err, 'sessionId': sessionId});

        // Never throw away what the user already said.

        if (_accumulatedTranscript.isNotEmpty) {
          _finishListening(reason: 'stt_error', submit: true);

          return;
        }

        _abortListening();
        _userKeepMicOn = false;
        state = state.copyWith(
          voiceState: VoiceState.error,

          isRecording: false,

          error: 'Lỗi micro / STT: $err',
        );
      },

      onDone: () {
        if (!_isActiveSession(sessionId)) return;

        _handleRecognizerEnded(sessionId);
      },
    );
  }

  /// The recognizer closed while the user still wanted to talk (server/OS

  /// session limit, network blip). Keep the transcript and reopen a bounded

  /// number of times; the silence timer keeps running across the restart.

  void _handleRecognizerEnded(int sessionId) {
    _noSpeechTimer?.cancel();

    log('stt_session_done', {
      'sessionId': sessionId,

      'autoRestarts': _autoRestarts,

      'textLength': _accumulatedTranscript.length,
    });

    // Promote the in-flight partial so its words survive the boundary.

    if (_partialSegment.isNotEmpty) {
      _finalSegments.add(_partialSegment);

      _partialSegment = '';
    }

    final neverConnected =
        state.voiceState == VoiceState.connecting &&
        _autoRestarts == 0 &&
        _accumulatedTranscript.isEmpty;

    if (neverConnected) {
      _abortListening();

      state = state.copyWith(
        isRecording: false,

        voiceState: VoiceState.error,

        error: 'Kết nối STT đã đóng trước khi sẵn sàng.',
      );

      return;
    }

    final elapsed = _turnStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_turnStartedAt!);

    if (_autoRestarts < _config.maxAutoRestarts &&
        elapsed < _config.listenFor) {
      _autoRestarts++;

      log('stt_auto_restart', {'attempt': _autoRestarts});

      state = state.copyWith(voiceState: VoiceState.connecting);

      _openRecognizer();

      return;
    }

    if (_accumulatedTranscript.isNotEmpty) {
      _finishListening(reason: 'recognizer_ended', submit: true);
    } else {
      _abortListening();

      state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
    }
  }

  void _armNoSpeechTimer(int sessionId) {
    _noSpeechTimer?.cancel();

    _noSpeechTimer = Timer(_config.noSpeechTimeout, () {
      if (!_isActiveSession(sessionId)) return;

      if (_accumulatedTranscript.isNotEmpty) return;

      log('stt_no_speech_timeout', {'sessionId': sessionId});

      _abortListening();

      state = state.copyWith(
        isRecording: false,

        voiceState: VoiceState.error,

        error: 'Không nhận diện được giọng nói.',
      );
    });
  }

  void _handleTranscript(String text, bool isFinal) {
    if (state.voiceState == VoiceState.thinking ||
        state.voiceState == VoiceState.speaking ||
        state.voiceState == VoiceState.processing) {
      return;
    }

    final cleaned = text.trim();

    // Empty partials must never wipe accumulated text.

    if (cleaned.isEmpty) return;

    _noSpeechTimer?.cancel();

    _mergeSegment(cleaned, isFinal);

    state = state.copyWith(
      currentTranscript: _accumulatedTranscript,

      voiceState: VoiceState.listening,

      isRecording: true,

      error: null,
    );

    // Any recognised speech resets the silence window, so natural pauses

    // shorter than [pauseFor] keep the turn open.

    // When STT sends a final segment (isFinal == true), use the shorter finalPauseFor window.
    _silenceTimer?.cancel();
    final waitDuration = isFinal
        ? (_config.finalPauseFor ?? _config.pauseFor)
        : _config.pauseFor;
    _silenceTimer = Timer(waitDuration, () {
      if (!mounted || !_listeningTurnActive) return;

      log('silence_threshold_reached', {
        'textLength': _accumulatedTranscript.length,
      });

      _finishListening(reason: 'silence', submit: true);
    });
  }

  /// Merges a recognizer segment into the turn transcript. Handles engines

  /// that send per-segment results as well as ones that resend the whole

  /// utterance, and drops duplicate finals.

  void _mergeSegment(String text, bool isFinal) {
    final committed = _finalSegments.join(' ');

    var segment = text;

    if (committed.isNotEmpty &&
        segment.startsWith(committed) &&
        (segment.length == committed.length ||
            segment[committed.length] == ' ')) {
      segment = segment.substring(committed.length).trim();
    }

    if (isFinal) {
      _partialSegment = '';

      if (segment.isEmpty) return;

      if (_finalSegments.isNotEmpty && _finalSegments.last == segment) return;

      _finalSegments.add(segment);
    } else {
      _partialSegment = segment;
    }
  }

  /// Ends the listening turn and optionally submits the accumulated text.
  void _finishListening({required String reason, required bool submit}) {
    final text = _accumulatedTranscript.trim();
    final isDirectEdit = _isDirectTripEditMode;
    final targetTrip = _directEditTrip;
    final targetDay = _directEditTargetDay;

    log('stt_finish', {
      'reason': reason,
      'textLength': text.length,
      'isDirectEdit': isDirectEdit,
    });

    _abortListening();

    if (submit && text.isNotEmpty) {
      if (isDirectEdit && targetTrip != null) {
        state = state.copyWith(isRecording: false, currentTranscript: text);
        editCurrentOrSavedTrip(
          instruction: text,
          targetDay: targetDay,
          fallbackTrip: targetTrip,
        );
      } else {
        sendMessage(text, isVoiceMode: true);
      }
    } else {
      state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
    }
  }

  /// Stops the recognizer, invalidates pending callbacks and disables any
  /// automatic restart. Does not touch [state].
  void _abortListening() {
    _listeningTurnActive = false;
    _isDirectTripEditMode = false;
    _directEditTrip = null;
    _directEditTargetDay = null;
    _cancelTimers();
    _sessionId++;
    _audioService.stopRecording();
  }

  void _cancelTimers() {
    _silenceTimer?.cancel();

    _noSpeechTimer?.cancel();

    _maxSessionTimer?.cancel();
  }

  // ── Intent Detection Helpers (ported from Web useChat.ts & utils.ts) ─────

  static final RegExp _affirmativeIntentRegex = RegExp(
    r"(?:^|\b)(?:dạ\s+)?(?:có|tạo\s*đi|tạo\s*cho\s*mình|tạo\s*giúp|tạo\s*hộ|tạo\s*luôn|tạo\s*ngay|tạo\s*lịch(?:\s*trình)?(?:\s*đi|\s*luôn|\s*ngay|\s*nha|\s*nhé|\s*cho\s*mình|\s*giúp)?|đồng\s*ý|nhất\s*trí|chốt(?:\s*đơn|\s*nha|\s*nhé|\s*luôn)?|triển(?:\s*thôi|\s*đi|\s*luôn)?|duyệt(?:\s*luôn|\s*nha)?|lên\s*lịch(?:\s*đi|\s*trình|\s*kế\s*hoạch)?|làm\s*đi|làm\s*luôn|ok|okie|oke|uki|yes|yep|sure|let's\s*go|tiến\s*hành\s*đi|chuẩn\s*rồi|được\s*đấy|được\s*nha|ừ(?:\s*tạo\s*đi)?)\b",

    caseSensitive: false,
  );

  static String _removeVietnameseAccents(String str) {
    var result = str;

    const vietnamese =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';

    const nonVietnamese =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

    for (var i = 0; i < vietnamese.length; i++) {
      result = result.replaceAll(vietnamese[i], nonVietnamese[i]);
    }

    return result;
  }

  static bool isCreateItineraryCommand(String text) {
    final clean = text
        .toLowerCase()
        .replaceAll(RegExp(r"""[.,?!:;~^`'"()\[\]{}]"""), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.isEmpty) return false;

    final noAccent = _removeVietnameseAccents(clean);

    // Nếu câu mang động từ chỉnh sửa / thay đổi rõ ràng (không phải tạo mới từ đầu), không coi là lệnh tạo mới
    final hasExplicitEditVerb =
        RegExp(
          r'(?:^|\b)(?:chỉnh\s*sửa|sửa|chỉnh|đổi|thay\s*đổi|thay|thêm|bớt|xóa|xoá|bỏ|dời|chuyển|cập\s*nhật|rút\s*gọn|kéo\s*dài|hoàn\s*tác|quay\s*lại\s*lịch)\b',
          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:^|\b)(?:chinh\s*sua|sua|chinh|doi|thay\s*doi|thay|them|bot|xoa|bo|chuyen|cap\s*nhat|rut\s*gon|keo\s*dai|hoan\s*tac|quay\s*lai\s*lich)\b',
          caseSensitive: false,
        ).hasMatch(noAccent);

    final hasExplicitCreateNew =
        RegExp(
          r'(?:tạo|lên|lập|thiết\s*kế)\s+(?:lại\s+)?(?:lịch\s*trình|kế\s*hoạch|chuyến\s*đi)\s+(?:mới|khác)',
          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:tao|len|lap|thiet\s*ke)\s+(?:lai\s+)?(?:lich\s*trinh|ke\s*hoach|chuyen\s*di)\s+(?:moi|khac)',
          caseSensitive: false,
        ).hasMatch(noAccent);

    if (hasExplicitEditVerb && !hasExplicitCreateNew) {
      return false;
    }

    final hasActionVerb =
        RegExp(
          r'(?:hãy\s+)?(?:tạo|lên|lập|thiết\s*kế|xây\s*dựng|gợi\s*ý|chuẩn\s*bị|làm|viết)',

          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:hay\s+)?(?:tao|len|lap|thiet\s*ke|xay\s*dung|goi\s*y|chuan\s*bi|lam|viet)',

          caseSensitive: false,
        ).hasMatch(noAccent);

    final hasTargetNoun =
        RegExp(
          r'(?:lịch\s*trình|kế\s*hoạch|lộ\s*trình|tour|chuyến\s*đi)',

          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:lich\s*trinh|ke\s*hoach|lo\s*trinh|tour|chuyen\s*di)',

          caseSensitive: false,
        ).hasMatch(noAccent);

    if (hasActionVerb && hasTargetNoun) return true;

    if (RegExp(
          r'(?:tạo|lên|lập)\s*lịch\b',
          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:tao|len|lap)\s*lich\b',
          caseSensitive: false,
        ).hasMatch(noAccent)) {
      return true;
    }

    if (RegExp(
      r'(?:create|make|build|generate|plan)\s+(?:an?\s+)?(?:itinerary|trip|travel\s*plan)',

      caseSensitive: false,
    ).hasMatch(clean)) {
      return true;
    }

    return false;
  }

  bool _hasDestinationInContext(Map<String, dynamic>? ctx) {
    if (ctx == null) return false;

    final trip = ctx['trip'] as Map<String, dynamic>?;

    final dest = trip?['destination'] as Map<String, dynamic>?;

    final city = dest?['city']?.toString().trim();

    final country = dest?['country']?.toString().trim();

    final topDest = ctx['destination']?.toString().trim();

    return (city != null && city.isNotEmpty) ||
        (country != null &&
            country.isNotEmpty &&
            country.toLowerCase() != 'việt nam') ||
        (topDest != null && topDest.isNotEmpty);
  }

  bool _hasDurationInContext(Map<String, dynamic>? ctx) {
    if (ctx == null) return false;

    final trip = ctx['trip'] as Map<String, dynamic>?;

    final dates = trip?['dates'] as Map<String, dynamic>?;

    final duration = trip?['duration'] as Map<String, dynamic>?;

    return dates?['duration_days'] != null ||
        dates?['start_date'] != null ||
        duration?['days'] != null ||
        ctx['duration_days'] != null;
  }

  bool _isReadyInContext(Map<String, dynamic>? ctx) {
    if (ctx == null) return false;

    final pState = ctx['planning_state'] as Map<String, dynamic>?;

    if (pState != null) {
      if (pState['is_ready_to_generate'] == true ||
          pState['is_ready_for_generation'] == true) {
        return true;
      }
    }

    return _hasDestinationInContext(ctx);
  }

  bool _isValidPersistedTripId(String? id) {
    if (id == null) return false;
    final clean = id.trim();
    if (clean.isEmpty || clean == '0' || clean.toLowerCase() == 'null') {
      return false;
    }
    final parsed = int.tryParse(clean);
    return parsed != null && parsed > 0;
  }

  String? _activeTripIdFromState([Map<String, dynamic>? ctx]) {
    if (_isValidPersistedTripId(state.savedTripId)) {
      return state.savedTripId!.trim();
    }
    if (state.tripPreview != null &&
        _isValidPersistedTripId(state.tripPreview!.id)) {
      return state.tripPreview!.id.trim();
    }
    final c = ctx ?? state.planningContext;
    final tripMap = c?['trip'] as Map<String, dynamic>?;
    final tid = tripMap?['trip_id']?.toString();
    if (_isValidPersistedTripId(tid)) return tid!.trim();
    return null;
  }

  /// Trích xuất nhanh điểm đến và số ngày từ câu lệnh tạo lịch trình trực tiếp ở phía Client

  /// để gọi thẳng `/api/v1/trips/generate` mà không cần chờ qua bước trung gian `/api/v1/rag/ask`.

  Map<String, dynamic>? _extractQuickPlanningContext(String text) {
    final lower = text.toLowerCase();

    const destinations = <String, String>{
      'đà nẵng': 'Đà Nẵng',

      'da nang': 'Đà Nẵng',

      'hội an': 'Hội An',

      'hoi an': 'Hội An',

      'huế': 'Huế',

      'hue': 'Huế',

      'đà lạt': 'Đà Lạt',

      'da lat': 'Đà Lạt',

      'nha trang': 'Nha Trang',

      'phú quốc': 'Phú Quốc',

      'phu quoc': 'Phú Quốc',

      'hà nội': 'Hà Nội',

      'ha noi': 'Hà Nội',

      'hồ chí minh': 'TP. Hồ Chí Minh',

      'sài gòn': 'TP. Hồ Chí Minh',

      'sai gon': 'TP. Hồ Chí Minh',

      'quy nhơn': 'Quy Nhơn',

      'quy nhon': 'Quy Nhơn',

      'vũng tàu': 'Vũng Tàu',

      'vung tau': 'Vũng Tàu',

      'hạ long': 'Hạ Long',

      'ha long': 'Hạ Long',

      'sapa': 'Sa Pa',

      'sa pa': 'Sa Pa',

      'ninh bình': 'Ninh Bình',

      'ninh binh': 'Ninh Bình',

      'phan thiết': 'Phan Thiết',

      'mũi né': 'Mũi Né',

      'cần thơ': 'Cần Thơ',

      'hà giang': 'Hà Giang',
    };

    String? matchedCity;

    for (final entry in destinations.entries) {
      if (lower.contains(entry.key)) {
        matchedCity = entry.value;

        break;
      }
    }

    if (matchedCity == null) return null;

    int durationDays = 3;

    final dayMatch =
        RegExp(r'(\d+)\s*ngày', caseSensitive: false).firstMatch(lower) ??
        RegExp(
          r'(\d+)\s*ngay',
          caseSensitive: false,
        ).firstMatch(_removeVietnameseAccents(lower));

    if (dayMatch != null) {
      final parsed = int.tryParse(dayMatch.group(1) ?? '');

      if (parsed != null && parsed >= 1 && parsed <= 14) {
        durationDays = parsed;
      }
    }

    final existing = state.planningContext != null
        ? Map<String, dynamic>.from(state.planningContext!)
        : <String, dynamic>{};

    final existingTrip = existing['trip'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(existing['trip'] as Map<String, dynamic>)
        : <String, dynamic>{};

    existingTrip['destination'] = {'city': matchedCity, 'country': 'Việt Nam'};

    existingTrip['dates'] = {'duration_days': durationDays};

    existing['trip'] = existingTrip;

    existing['planning_state'] = {'is_ready_to_generate': true};

    return existing;
  }

  /// Kiểm tra nhanh câu nói có khả năng là lệnh chỉnh sửa lịch trình hay không

  /// (giúp câu hỏi thông thường bỏ qua lời gọi LLM `/detect-intent` tốn 2-3 giây).

  bool _looksLikePotentialEditRequest(String text) {
    final lower = text.toLowerCase();
    final noAccent = _removeVietnameseAccents(lower);
    final hasEditCue =
        RegExp(
          r'(?:thêm|bớt|xóa|xoá|bỏ|đổi|thay|sửa|dời|chuyển|cập\s*nhật|chỉnh|sắp\s*xếp|rút\s*gọn|kéo\s*dài|bắt\s*đầu|kết\s*thúc|lúc\s*\d|ngày\s*(?:thứ\s*)?\d|buổi\s*(?:sáng|trưa|chiều|tối)|chiều\s*nay|sáng\s*mai|tối\s*nay|nghỉ\s*ngơi|nghỉ\s*(?:ở\s*)?khách\s*sạn|mệt|ngủ\s*nướng|dậy\s*(?:muộn|trễ)|sớm\s*hơn|muộn\s*hơn|trễ\s*hơn|không\s*thích|chỗ\s*khác|gần\s*hơn|xa\s*quá|quay\s*lại|hoàn\s*tác|lịch\s*cũ|như\s*cũ|trước\s*khi\s*sửa|giữ\s*nguyên|nhẹ\s*nhàng|thư\s*thả|thong\s*thả|thay\s*vì|không\s*muốn\s*đi|ghé\s*thêm|cho\s*thêm|cho\s*(?:mình|tôi|em)\s*đi|muốn\s*(?:đi\s*thêm|ghé|ăn|đổi|thêm)|xếp\s*thêm|đưa\s*thêm|mưa)',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(
          r'(?:them|bot|xoa|bo|doi|thay|sua|chuyen|cap\s*nhat|chinh|sap\s*xep|rut\s*gon|keo\s*dai|bat\s*dau|ket\s*thuc|luc\s*\d|ngay\s*(?:thu\s*)?\d|buoi\s*(?:sang|trua|chieu|toi)|chieu\s*nay|sang\s*mai|nghi|met|ngu\s*nuong|day\s*(?:muon|tre)|som\s*hon|muon\s*hon|tre\s*hon|khong\s*thich|cho\s*khac|gan\s*hon|xa\s*qua|quay\s*lai|hoan\s*tac|lich\s*cu|nhu\s*cu|giu\s*nguyen|nhe\s*nhang|thong\s*tha|muon\s*(?:di\s*them|ghe|an|doi|them)|mua)',
          caseSensitive: false,
        ).hasMatch(noAccent);
    return hasEditCue;
  }

  /// Kiểm tra xem người dùng có ý định lưu chuyến đi / bản nháp hay không
  bool _looksLikeSaveTripRequest(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;
    final noAccent = _removeVietnameseAccents(lower);

    // 1. Nhận diện các cụm từ chứa 'lưu' hoặc 'save'
    final savePhrases = RegExp(
      r'(?:^|\b)(?:lưu|luu|save|xác\s*nhận|xac\s*nhan)\s*(?:lại\s*|lai\s*)?(?:chuyến\s*đi|chuyen\s*di|lịch\s*trình|lich\s*trinh|bản\s*nháp|ban\s*nhap|kế\s*hoạch|ke\s*hoach|tour)?',
      caseSensitive: false,
    );
    if (savePhrases.hasMatch(lower) || savePhrases.hasMatch(noAccent)) {
      if (lower.contains('lưu ý') ||
          lower.contains('luu y') ||
          lower.contains('lưu niệm') ||
          lower.contains('luu niem') ||
          lower.contains('lưu thông') ||
          lower.contains('luu thong')) {
        return false;
      }
      return true;
    }

    // 2. Các câu ngắn gọn: "lưu đi", "lưu lại", "lưu nhé", "lưu nha", "save it", "lưu bản nháp"
    final shortSave = RegExp(
      r'^(?:lưu|luu|save)(?:\s*(?:lại|lai|đi|di|nha|nhé|nhe|luôn|luon|giúp|gium|hộ|ho|it|nay|này|đó|do))?$',
      caseSensitive: false,
    );
    return shortSave.hasMatch(lower) || shortSave.hasMatch(noAccent);
  }

  // ── Send message (RAG ask + Web useChat.ts Itinerary Flow) ───────────────

  Future<void> sendMessage(
    String text, {

    bool isVoiceMode = false,

    List<ChatMedia> media = const [],
  }) async {
    _isVoiceSession = isVoiceMode;

    final trimmed = text.trim();

    if (trimmed.isEmpty && media.isEmpty) return;

    if (_isCommitting ||
        state.voiceState == VoiceState.thinking ||
        state.voiceState == VoiceState.processing ||
        state.planningState == TripPlanningState.generating ||
        state.planningState == TripPlanningState.revising) {
      log('rag_submit_skipped_busy', {'voiceState': state.voiceState.name});

      return;
    }

    if (isVoiceMode &&
        _lastSubmittedTranscript != null &&
        _lastSubmittedTranscript == trimmed) {
      log('rag_submit_skipped_duplicate', {'textLength': trimmed.length});

      return;
    }

    final reqGen = ++_requestGeneration;
    _isCommitting = true;
    _abortListening();
    stopAudio();
    _lastSubmittedTranscript = trimmed;

    log('rag_submit', {
      'textLength': trimmed.length,

      'mediaCount': media.length,

      'conversationId': state.conversationId,

      'isVoiceMode': isVoiceMode,
    });

    final effectiveText = trimmed.isNotEmpty
        ? trimmed
        : (media.isNotEmpty
              ? (media.first.isVideo
                    ? 'Đã gửi 1 video'
                    : 'Đã gửi ${media.length} hình ảnh')
              : '');

    final userMsg = ChatMessage(
      text: effectiveText,

      isUser: true,

      timestamp: DateTime.now(),

      media: media,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],

      voiceState: isVoiceMode ? VoiceState.processing : VoiceState.thinking,

      currentTranscript: trimmed,

      isRecording: false,

      error: null,
    );

    try {
      final ctx = state.planningContext;

      final hasDestination = _hasDestinationInContext(ctx);

      final hasDuration = _hasDurationInContext(ctx);

      final isReadyToGenerate =
          _isReadyInContext(ctx) ||
          state.planningState == TripPlanningState.readyToGenerate;

      final isCreateCmd = isCreateItineraryCommand(trimmed);

      final isAffirmative =
          isCreateCmd ||
          _affirmativeIntentRegex.hasMatch(trimmed) ||
          RegExp(
            r'(?:tạo|lên|lập)\s*(?:cho\s*[\w\s]+\s+)?(?:lịch\s*trình|kế\s*hoạch|lịch|tour)?\s*(?:đi|luôn|ngay|nha|nhé|giúp|hộ)',

            caseSensitive: false,
          ).hasMatch(trimmed) ||
          (trimmed.length <= 30 &&
              RegExp(
                r'^(dạ\s+)?(có|tạo|ok|được|làm|yes|đồng ý|nhất trí|chốt|triển|hãy tạo|cứ tạo)',

                caseSensitive: false,
              ).hasMatch(trimmed));

      // 1. Kiểm tra ý định XÓA / HỦY LỊCH TRÌNH (giống Web useChat.ts)

      final isClearIntent =
          RegExp(
            r'(?:xóa|xoá|hủy|bỏ|reset|clear)\s+(?:lịch\s*trình|kế\s*hoạch)(?:\s+(?:này|hiện\s*tại|đi|giúp\s*mình|hộ\s*mình))?',

            caseSensitive: false,
          ).hasMatch(trimmed) &&
          !RegExp(
            r'(?:thêm|sửa|đổi|ngày\s*\d)',
            caseSensitive: false,
          ).hasMatch(trimmed);

      if (isClearIntent) {
        final hadItin = state.tripPreview != null;

        state = state.copyWith(
          clearTripPreview: true,

          planningState: TripPlanningState.idle,
        );

        _ref.read(currentTripPreviewProvider.notifier).state = null;

        final replyContent = hadItin
            ? 'Mình đã xóa lịch trình hiện tại cho bạn rồi nhé! Bây giờ bạn có thể chia sẻ điểm đến, số ngày hoặc yêu cầu mới để mình lên lại lịch trình khác cho bạn nhé!'
            : 'Hiện tại chưa có lịch trình nào đang mở để xóa bạn nhé! Bạn có thể chia sẻ điểm đến hoặc yêu cầu để mình tạo lịch trình mới ngay.';

        final aiMsg = ChatMessage(
          text: replyContent,

          isUser: false,

          timestamp: DateTime.now(),
        );

        state = state.copyWith(
          messages: [...state.messages, aiMsg],

          currentTranscript: replyContent,
        );

        if (isVoiceMode || state.isTtsEnabled) {
          await _playTts(replyContent);
        } else {
          state = state.copyWith(voiceState: VoiceState.idle);
        }

        return;
      }

      // 2. Kiểm tra ý định TẠO LẠI LỊCH TRÌNH KHÁC (giống Web useChat.ts)

      final isRegenerateIntent =
          RegExp(
            r'(?:tạo\s*lại|làm\s*lại|lên\s*lại|thiết\s*kế\s*lại)\s+(?:lịch\s*trình|kế\s*hoạch)(?:\s+(?:khác|mới|đi|cho\s*mình|giúp\s*mình))?',

            caseSensitive: false,
          ).hasMatch(trimmed) ||
          RegExp(
            r'(?:tạo|lên|làm)\s+(?:lịch\s*trình|kế\s*hoạch)\s+khác',

            caseSensitive: false,
          ).hasMatch(trimmed);

      if (isRegenerateIntent &&
          hasDestination &&
          state.conversationId != null) {
        state = state.copyWith(clearTripPreview: true);

        await generateItinerary(
          convId: state.conversationId,

          userPrompt:
              'Tạo lại lịch trình khác với các địa điểm và hoạt động mới mẻ hơn',
        );

        return;
      }

      // 3. Nếu người dùng ra lệnh tạo lịch trình trực tiếp có sẵn điểm đến (VD: "Tạo lịch trình đi Đà Nẵng 3 ngày")

      //    -> Gọi thẳng generateItinerary với quick context (bỏ qua bước chờ /rag/ask trung gian để phản hồi nhanh gấp đôi)

      if (isCreateCmd) {
        final quickCtx = _extractQuickPlanningContext(trimmed);

        if (quickCtx != null) {
          state = state.copyWith(
            clearTripPreview: true,

            planningContext: quickCtx,

            planningState: TripPlanningState.readyToGenerate,
          );

          await generateItinerary(
            convId: state.conversationId,

            context: quickCtx,

            userPrompt: trimmed,
          );

          return;
        }
      }

      // 3b. Nếu đã có điểm đến trong context và người dùng xác nhận "Tạo đi" / "Đồng ý" / "Ok"

      //     (và câu ngắn không chứa thông tin điểm đến mới) -> Tạo lịch trình ngay lập tức

      final hasNewPlaceOrDaysInPrompt = RegExp(
        r'(?:đi\s+\S+|\d+\s*ngày|\d+\s*đêm)',

        caseSensitive: false,
      ).hasMatch(trimmed);

      if (hasDestination &&
          (hasDuration || isReadyToGenerate || isCreateCmd) &&
          isAffirmative &&
          !hasNewPlaceOrDaysInPrompt &&
          state.conversationId != null) {
        state = state.copyWith(clearTripPreview: true);

        await generateItinerary(
          convId: state.conversationId,

          userPrompt: trimmed,
        );

        return;
      }

      // 3c. Fast-path: Người dùng yêu cầu LƯU CHUYẾN ĐI / BẢN NHÁP (VD: "Lưu chuyến đi", "Lưu bản nháp", "Lưu lại nhé")
      if (_looksLikeSaveTripRequest(trimmed)) {
        if (state.tripPreview != null) {
          final alreadySaved =
              state.planningState == TripPlanningState.saved ||
              (state.savedTripId != null &&
                  state.savedTripId!.isNotEmpty &&
                  state.savedTripId != '0' &&
                  state.tripPreview?.status == 'CONFIRMED');

          if (alreadySaved) {
            final alreadySavedMsg =
                'Chuyến đi "${state.tripPreview!.title}" đã được lưu an toàn trong danh sách của bạn rồi nhé! Bạn có thể xem lại trong mục Chuyến đi bất cứ lúc nào.';
            final aiMsg = ChatMessage(
              text: alreadySavedMsg,
              isUser: false,
              timestamp: DateTime.now(),
              tripItinerary: state.tripPreview,
            );
            state = state.copyWith(
              messages: [...state.messages, aiMsg],
              currentTranscript: alreadySavedMsg,
              voiceState: VoiceState.idle,
            );
            if (_isVoiceSession) {
              _userKeepMicOn = true;
            }
            if (state.isTtsEnabled) {
              _ttsCancelled = false;
              await _playTts(alreadySavedMsg);
            } else {
              _resumeListeningIfPersistent();
            }
            return;
          }

          // Gọi API lưu chuyến đi bản nháp vào CSDL
          await saveCurrentTrip();
          return;
        } else {
          // Chưa có bản nháp lịch trình nào để lưu
          const noTripMsg =
              'Hiện tại chưa có bản nháp lịch trình nào để lưu. Bạn hãy nói "Tạo lịch trình đi Đà Nẵng 3 ngày" để mình tạo lịch trình mới cho bạn nhé!';
          final aiMsg = ChatMessage(
            text: noTripMsg,
            isUser: false,
            timestamp: DateTime.now(),
          );
          state = state.copyWith(
            messages: [...state.messages, aiMsg],
            currentTranscript: noTripMsg,
            voiceState: VoiceState.idle,
          );
          if (_isVoiceSession) {
            _userKeepMicOn = true;
          }
          if (state.isTtsEnabled) {
            _ttsCancelled = false;
            await _playTts(noTripMsg);
          } else {
            _resumeListeningIfPersistent();
          }
          return;
        }
      }

      // 4. Tự động xác định ý định CHỈNH SỬA LỊCH TRÌNH (Fast-path: Gọi thẳng /itinerary/edit khi có dấu hiệu sửa,

      //    bỏ qua bước gọi trùng lặp /detect-intent vì /itinerary/edit đã tự kiểm tra intent và trả ANSWERED nếu là câu hỏi)

      if ((state.tripPreview != null || _activeTripIdFromState() != null) &&
          !isCreateCmd &&
          !isRegenerateIntent &&
          _looksLikePotentialEditRequest(trimmed)) {
        await editCurrentOrSavedTrip(instruction: trimmed);
        return;
      }

      // 5. Hỏi đáp AI siêu tốc qua SSE Streaming (/api/v1/rag/ask-stream) kết hợp phát giọng nói từng câu tức thì

      final shouldSpeak = isVoiceMode || state.isTtsEnabled;

      final imageUrls = media
          .where((m) => m.isImage)
          .map((m) => m.url)
          .toList();

      final streamHandled = await _askRagStream(
        trimmed,
        reqGen: reqGen,
        isVoiceMode: isVoiceMode,
        shouldSpeak: shouldSpeak,
        isCreateCmd: isCreateCmd,
        isAffirmative: isAffirmative,
        isRegenerateIntent: isRegenerateIntent,
        media: media,
      );

      if (streamHandled) {
        return;
      }

      // Fallback sang /api/v1/rag/ask đồng bộ nếu stream không khả dụng

      final response = await _dio.post(
        '/api/v1/rag/ask',

        data: {
          'message': trimmed,

          if (state.conversationId != null)
            'conversation_id': state.conversationId,

          if (imageUrls.isNotEmpty) 'image_urls': imageUrls,

          'mode': isVoiceMode ? 'voice' : 'chat',
        },
      );

      if (!mounted || _requestGeneration != reqGen) return;

      log('rag_response', {'statusCode': response.statusCode});

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        final content =
            (data['message'] as Map<String, dynamic>)['content'] as String;

        final convId = data['conversation_id'] as int?;

        final planningStatus = data['planning_status']?.toString();

        final isReady = data['is_ready_to_generate'] == true;

        final planningAction = data['planning_action']?.toString();

        final planningCtx = data['planning_context'] as Map<String, dynamic>?;

        bool isReadyFromCtx = _isReadyInContext(planningCtx);

        bool hasDestAfterAsk = _hasDestinationInContext(planningCtx);

        String? ctxTripId;

        if (planningCtx != null) {
          final tripMap = planningCtx['trip'] as Map<String, dynamic>?;

          ctxTripId = tripMap?['trip_id']?.toString();
        }

        log('rag_success', {
          'contentLength': content.length,

          'conversationId': convId,

          'planningStatus': planningStatus,

          'isReady': isReady || isReadyFromCtx,

          'hasDestAfterAsk': hasDestAfterAsk,

          'planningAction': planningAction,
        });

        final rawMedia = data['media'] as List<dynamic>?;

        final aiMedia = rawMedia != null
            ? rawMedia
                  .whereType<Map<String, dynamic>>()
                  .map((m) => ChatMedia.fromJson(m))
                  .toList()
            : const <ChatMedia>[];

        final aiMsg = ChatMessage(
          text: content,

          isUser: false,

          timestamp: DateTime.now(),

          media: aiMedia,
        );

        TripPlanningState derivedPlanning = state.planningState;

        if (planningStatus == 'collecting_requirements') {
          derivedPlanning = TripPlanningState.collectingRequirements;
        } else if (planningStatus == 'ready_to_generate' ||
            isReady ||
            isReadyFromCtx ||
            hasDestAfterAsk) {
          derivedPlanning = TripPlanningState.readyToGenerate;
        }

        final summary =
            _formatPlanningContextSummary(planningCtx) ??
            state.planningContextSummary;

        state = state.copyWith(
          messages: [...state.messages, aiMsg],

          conversationId: convId,

          currentTranscript: content,

          planningState: derivedPlanning,

          planningContextSummary: summary,

          planningContext: planningCtx,

          savedTripId: (ctxTripId != null && ctxTripId.isNotEmpty)
              ? ctxTripId
              : state.savedTripId,
        );

        if (isVoiceMode || state.isTtsEnabled) {
          await _playTts(content);
        } else {
          state = state.copyWith(voiceState: VoiceState.idle);
        }

        final shouldAutoGenerate =
            convId != null &&
            (planningAction == 'TRIGGER_GENERATION' ||
                ((isCreateCmd || isAffirmative || isRegenerateIntent) &&
                    (derivedPlanning == TripPlanningState.readyToGenerate ||
                        hasDestAfterAsk)));

        if (shouldAutoGenerate) {
          await generateItinerary(
            convId: convId,

            context: planningCtx,

            userPrompt: trimmed,
          );
        } else if (planningAction == 'TRIGGER_SAVE' &&
            state.tripPreview != null &&
            convId != null) {
          await saveCurrentTrip(convId: convId);
        } else if (planningAction == 'TRIGGER_EDIT') {
          final targetTripId =
              state.savedTripId ??
              (state.tripPreview?.id != null &&
                      state.tripPreview!.id.isNotEmpty &&
                      state.tripPreview!.id != '0'
                  ? state.tripPreview!.id.toString()
                  : null);

          if (targetTripId != null && targetTripId.isNotEmpty) {
            await editSavedTrip(tripId: targetTripId, instruction: trimmed);
          }
        }
      } else {
        state = state.copyWith(
          voiceState: VoiceState.error,

          error: 'Lỗi từ máy chủ AI ()',
        );

        return;
      }
    } on DioException catch (e) {
      if (!mounted) return;

      final errDetail = e.response?.data?['detail']?.toString() ?? e.message;

      log('rag_dio_error', {
        'statusCode': e.response?.statusCode,

        'detail': errDetail,
      });

      state = state.copyWith(
        voiceState: VoiceState.error,

        error: 'Lỗi kết nối: $errDetail',
      );
    } catch (e) {
      if (!mounted) return;

      log('rag_unexpected_error', {'error': e.toString()});

      state = state.copyWith(
        voiceState: VoiceState.error,

        error: 'Lỗi hệ thống: $e',
      );
    } finally {
      if (_requestGeneration == reqGen) {
        _isCommitting = false;
      }
      if (mounted) {
        _dedupeResetTimer?.cancel();
        _dedupeResetTimer = Timer(const Duration(seconds: 2), () {
          if (_lastSubmittedTranscript == trimmed) {
            _lastSubmittedTranscript = null;
          }
        });
      }
    }
  }

  // ── SSE Streaming RAG + Realtime Sentence TTS Queue ─────────────────────

  /// Extracts the next speakable text chunk from [buffer], returning
  /// `(chunk, remainder)` or `null` if more tokens are needed.
  ///
  /// For the very first chunk ([isFirstChunk] == true), splits earlier on
  /// natural clause pauses (`,`, `;`, `:`, `–`, `—`) once >= 22 characters
  /// have accumulated so TTS audio starts playing with minimal TTFB.
  static ({String chunk, String remainder})? extractNextTtsChunk(
    String buffer, {
    required bool isFirstChunk,
  }) {
    if (buffer.isEmpty) return null;

    final abbrevSuffix = RegExp(
      r'(?:^|\s)(?:tp|q|p|tt|mr|mrs|ms|dr|st|no|ths|pgs|gs|ts)\.$',
      caseSensitive: false,
    );

    final sentenceRegex = RegExp(r'[.!?\n](?:\s+|$)');
    for (final match in sentenceRegex.allMatches(buffer)) {
      final matchedText = match.group(0)!;
      // Wait for trailing whitespace after '.', '!', '?' so decimals like "4.5"
      // mid-stream are never split prematurely; '\n' can split immediately.
      if (matchedText.length == 1 && matchedText != '\n') {
        continue;
      }
      final candidate = buffer.substring(0, match.start + 1).trim();
      final minLen = isFirstChunk ? 4 : 10;
      if (candidate.length >= minLen && !abbrevSuffix.hasMatch(candidate)) {
        return (chunk: candidate, remainder: buffer.substring(match.end));
      }
    }

    final clauseMinLen = isFirstChunk ? 10 : 50;
    if (buffer.length >= clauseMinLen) {
      final clauseRegex = RegExp(r'[,;:–—]\s+');
      for (final match in clauseRegex.allMatches(buffer)) {
        final candidate = buffer.substring(0, match.start + 1).trim();
        if (candidate.length >= clauseMinLen) {
          return (chunk: candidate, remainder: buffer.substring(match.end));
        }
      }
    }

    return null;
  }

  Stream<String> _openRagSseStream(Map<String, dynamic> payload) async* {
    if (useNativeFetchStream) {
      String? token;
      try {
        token = await _ref.read(secureStorageProvider).getToken();
      } on CacheException catch (e) {
        log('sse_token_read_skipped', {'message': e.message});
      }
      final baseUrl = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
      yield* _audioService.askStream(
        url: '$baseUrl/api/v1/rag/ask-stream',
        token: token,
        bodyJson: jsonEncode(payload),
      );
      return;
    }

    final response = await _dio.post<ResponseBody>(
      '/api/v1/rag/ask-stream',
      data: payload,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('SSE HTTP ${response.statusCode}');
    }
    yield* utf8.decoder.bind(response.data!.stream);
  }

  /// Gọi `/api/v1/rag/ask-stream` để stream từng token câu trả lời thời gian thực
  /// và đẩy từng mệnh đề/câu vào hàng đợi âm thanh ngay khi vừa xuất hiện.
  Future<bool> _askRagStream(
    String trimmed, {
    required int reqGen,
    required bool isVoiceMode,
    required bool shouldSpeak,
    required bool isCreateCmd,
    required bool isAffirmative,
    required bool isRegenerateIntent,
    List<ChatMedia> media = const [],
  }) async {
    try {
      final imageUrls = media
          .where((m) => m.isImage)
          .map((m) => m.url)
          .toList();
      final payload = <String, dynamic>{
        'message': trimmed,
        if (state.conversationId != null)
          'conversation_id': state.conversationId,
        if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
        // When image is attached, mode 'chat' ensures detailed vision explanation!
        'mode': imageUrls.isNotEmpty ? 'chat' : 'voice',
      };

      if (shouldSpeak) {
        prepareForTtsPlayback();
        _audioService.initStreamingQueue(
          onPlay: () {
            if (!mounted || _requestGeneration != reqGen) return;
            if (_ttsCancelled) {
              _audioService.stopTts();
              return;
            }
            log('tts_stream_playback_started');
            state = state.copyWith(
              voiceState: VoiceState.speaking,
              error: null,
            );
          },
          onEnded: () {
            if (!mounted || _requestGeneration != reqGen) return;
            log('tts_stream_playback_finished');
            if (state.planningState != TripPlanningState.generating &&
                state.planningState != TripPlanningState.revising) {
              _resumeListeningIfPersistent();
            }
          },
          onError: (err) {
            if (!mounted || _requestGeneration != reqGen) return;
            log('tts_stream_playback_error', {'error': err});
            if (state.planningState != TripPlanningState.generating &&
                state.planningState != TripPlanningState.revising) {
              _resumeListeningIfPersistent();
            }
          },
        );
      }

      final baseMessages = List<ChatMessage>.from(state.messages);
      String accumulatedText = '';
      String sentenceBuffer = '';
      String sseBuffer = '';
      int? convId = state.conversationId;
      Map<String, dynamic>? planningCtx = state.planningContext;
      String? streamPlanningAction;
      String? streamPlanningStatus;
      bool streamIsReadyFlag = false;
      bool enqueuedAnySentence = false;
      List<ChatMedia> streamMedia = const [];
      final uiThrottleClock = Stopwatch()..start();
      int lastUiFlushMs = -1000;

      void flushStreamingUi() {
        if (!mounted ||
            _requestGeneration != reqGen ||
            accumulatedText.isEmpty) {
          return;
        }
        final streamingMsg = ChatMessage(
          text: accumulatedText,
          isUser: false,
          timestamp: DateTime.now(),
          media: streamMedia,
        );
        state = state.copyWith(
          messages: [...baseMessages, streamingMsg],
          currentTranscript: accumulatedText,
        );
        lastUiFlushMs = uiThrottleClock.elapsedMilliseconds;
      }

      final textStream = _openRagSseStream(payload);
      await for (final chunkText in textStream) {
        if (!mounted || _requestGeneration != reqGen) return true;
        sseBuffer += chunkText;

        while (sseBuffer.contains('\n\n')) {
          final splitIdx = sseBuffer.indexOf('\n\n');
          final rawEvent = sseBuffer.substring(0, splitIdx).trim();
          sseBuffer = sseBuffer.substring(splitIdx + 2);

          if (!rawEvent.startsWith('data:')) continue;
          final jsonStr = rawEvent.substring(5).trim();
          if (jsonStr.isEmpty) continue;

          Map<String, dynamic> eventData;
          try {
            eventData = jsonDecode(jsonStr) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          final type = eventData['type']?.toString();
          if (type == 'init') {
            final initConvId = eventData['conversation_id'];
            if (initConvId is int) {
              convId = initConvId;
              state = state.copyWith(conversationId: convId);
            }
          } else if (type == 'media') {
            final rawMediaList = eventData['media'] as List<dynamic>?;
            if (rawMediaList != null) {
              streamMedia = rawMediaList
                  .whereType<Map<String, dynamic>>()
                  .map((m) => ChatMedia.fromJson(m))
                  .toList();
              flushStreamingUi();
            }
          } else if (type == 'token') {
            final token = eventData['token']?.toString() ?? '';
            if (token.isEmpty) continue;

            accumulatedText += token;

            // Dispatch speakable clauses/sentences immediately on arrival (0ms throttle)
            if (shouldSpeak && !_ttsCancelled) {
              sentenceBuffer += token;
              while (!_ttsCancelled) {
                final extracted = extractNextTtsChunk(
                  sentenceBuffer,
                  isFirstChunk: !enqueuedAnySentence,
                );
                if (extracted == null) break;
                sentenceBuffer = extracted.remainder;
                final cleanedSentence = _cleanTextForTts(extracted.chunk);
                if (cleanedSentence.isNotEmpty && !_ttsCancelled) {
                  enqueuedAnySentence = true;
                  _audioService.enqueueSentence(
                    baseUrl: ApiConfig.baseUrl,
                    sentence: cleanedSentence,
                    speed: state.ttsSpeed,
                    speakerId: state.speakerId,
                  );
                }
              }
            }

            // Throttle widget tree rebuilds (~20fps) so main thread stays free for audio
            if (uiThrottleClock.elapsedMilliseconds - lastUiFlushMs >= 45) {
              flushStreamingUi();
            }
          } else if (type == 'done') {
            if (eventData['conversation_id'] is int) {
              convId = eventData['conversation_id'] as int;
            }
            final doneContent = eventData['content']?.toString().trim();
            if (doneContent != null && doneContent.isNotEmpty) {
              accumulatedText = doneContent;
            }
            if (eventData['planning_context'] is Map<String, dynamic>) {
              planningCtx =
                  eventData['planning_context'] as Map<String, dynamic>;
            }
            if (eventData['planning_action'] != null) {
              streamPlanningAction = eventData['planning_action'].toString();
            }
            if (eventData['planning_status'] != null) {
              streamPlanningStatus = eventData['planning_status'].toString();
            }
            if (eventData['is_ready_to_generate'] == true) {
              streamIsReadyFlag = true;
            }
            if (eventData['media'] is List) {
              final rawMediaList = eventData['media'] as List<dynamic>;
              streamMedia = rawMediaList
                  .whereType<Map<String, dynamic>>()
                  .map((m) => ChatMedia.fromJson(m))
                  .toList();
            }
          } else if (type == 'error') {
            throw Exception(
              eventData['message']?.toString() ?? 'Lỗi tạo câu trả lời',
            );
          }
        }
      }

      if (!mounted || _requestGeneration != reqGen) return true;
      if (accumulatedText.trim().isEmpty) {
        return false;
      }

      if (shouldSpeak && !_ttsCancelled && sentenceBuffer.trim().isNotEmpty) {
        final cleanedTail = _cleanTextForTts(sentenceBuffer.trim());
        if (cleanedTail.isNotEmpty) {
          enqueuedAnySentence = true;
          _audioService.enqueueSentence(
            baseUrl: ApiConfig.baseUrl,
            sentence: cleanedTail,
            speed: state.ttsSpeed,
            speakerId: state.speakerId,
          );
        }
        sentenceBuffer = '';
      }

      final finalMsg = ChatMessage(
        text: accumulatedText,
        isUser: false,
        timestamp: DateTime.now(),
        media: streamMedia,
      );

      final isReadyFromCtx = _isReadyInContext(planningCtx);
      final hasDestAfterAsk = _hasDestinationInContext(planningCtx);
      String? ctxTripId;
      if (planningCtx != null) {
        final tripMap = planningCtx['trip'] as Map<String, dynamic>?;
        ctxTripId = tripMap?['trip_id']?.toString();
      }

      TripPlanningState derivedPlanning = state.planningState;
      if (state.tripPreview == null) {
        if (streamPlanningStatus == 'collecting_requirements') {
          derivedPlanning = TripPlanningState.collectingRequirements;
        } else if (streamPlanningStatus == 'ready_to_generate' ||
            streamIsReadyFlag ||
            isReadyFromCtx ||
            hasDestAfterAsk) {
          derivedPlanning = TripPlanningState.readyToGenerate;
        }
      }

      final summary =
          _formatPlanningContextSummary(planningCtx) ??
          state.planningContextSummary;

      state = state.copyWith(
        messages: [...baseMessages, finalMsg],
        conversationId: convId,
        currentTranscript: accumulatedText,
        planningState: derivedPlanning,
        planningContextSummary: summary,
        planningContext: planningCtx,
        savedTripId: (ctxTripId != null && ctxTripId.isNotEmpty)
            ? ctxTripId
            : state.savedTripId,
      );

      final shouldAutoGenerate =
          convId != null &&
          (streamPlanningAction == 'TRIGGER_GENERATION' ||
              ((isCreateCmd || isAffirmative || isRegenerateIntent) &&
                  (derivedPlanning == TripPlanningState.readyToGenerate ||
                      hasDestAfterAsk)));

      if (shouldAutoGenerate) {
        _audioService.stopTts();
        await generateItinerary(
          convId: convId,
          context: planningCtx,
          userPrompt: trimmed,
        );
      } else if (streamPlanningAction == 'TRIGGER_EDIT' &&
          (state.tripPreview != null ||
              _activeTripIdFromState(planningCtx) != null)) {
        _audioService.stopTts();
        await editCurrentOrSavedTrip(instruction: trimmed);
      } else if (streamPlanningAction == 'TRIGGER_SAVE' &&
          state.tripPreview != null &&
          convId != null) {
        _audioService.stopTts();
        await saveCurrentTrip(convId: convId);
      } else if (shouldSpeak && !_ttsCancelled) {
        if (enqueuedAnySentence) {
          _audioService.markStreamDone();
        } else {
          await _playTts(accumulatedText);
        }
      } else {
        state = state.copyWith(voiceState: VoiceState.idle);
      }

      return true;
    } catch (e) {
      log('rag_stream_fallback', {'error': e.toString()});
      return false;
    }
  }

  // ── Trip Planning Generation & Persistence ──────────────────────────────

  /// Validates planning context from backend before generating itinerary.

  Future<void> requestGenerateItinerary({
    int? convId,
    String? userPrompt,
  }) async {
    final cid = convId ?? state.conversationId;

    if (cid == null) {
      const warnMsg =
          'Bạn hãy nói hoặc nhập điểm đến và thời gian chuyến đi (ví dụ: "Tạo lịch trình đi Đà Nẵng 3 ngày") để mình hỗ trợ tạo lịch trình nhé!';

      final aiMsg = ChatMessage(
        text: warnMsg,

        isUser: false,

        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, aiMsg],

        currentTranscript: warnMsg,
      );

      if (state.isTtsEnabled) await _playTts(warnMsg);

      return;
    }

    if (state.planningState == TripPlanningState.generating) return;

    Map<String, dynamic>? ctx = state.planningContext;

    try {
      final serverCtx = await _tripRepo.getPlanningContext(cid);

      if (serverCtx != null) {
        ctx = serverCtx;
      }
    } catch (_) {}

    if (ctx != null) {
      final hasDest = _hasDestinationInContext(ctx);

      final isReady = _isReadyInContext(ctx);

      if (!hasDest && !isReady) {
        const promptMsg =
            'AI cần biết thêm điểm đến và số ngày cho chuyến đi của bạn (ví dụ: "Đà Nẵng 3 ngày"). Bạn hãy cung cấp thêm thông tin nhé!';

        final aiMsg = ChatMessage(
          text: promptMsg,

          isUser: false,

          timestamp: DateTime.now(),
        );

        state = state.copyWith(
          messages: [...state.messages, aiMsg],

          currentTranscript: promptMsg,

          planningState: TripPlanningState.collectingRequirements,
        );

        if (state.isTtsEnabled) await _playTts(promptMsg);

        return;
      }
    }

    await generateItinerary(convId: cid, context: ctx, userPrompt: userPrompt);
  }

  Future<void> generateItinerary({
    int? convId,

    Map<String, dynamic>? context,

    String? userPrompt,
  }) async {
    final cid = convId ?? state.conversationId;

    if (cid == null && context == null) return;

    if (state.planningState == TripPlanningState.generating) {
      log('generate_itinerary_skipped_already_busy');

      return;
    }

    final effectiveCtx = context ?? state.planningContext;

    log('generating_itinerary', {'conversationId': cid});

    state = state.copyWith(
      planningState: TripPlanningState.generating,
      voiceState: VoiceState.processing,
      error: null,
    );

    if (_isVoiceSession && state.isTtsEnabled && !state.isMuted) {
      final tripMap = effectiveCtx?['trip'] as Map<String, dynamic>?;
      final destMap = tripMap?['destination'] as Map<String, dynamic>?;
      final city = destMap?['city']?.toString().trim();
      final filler = (city != null && city.isNotEmpty)
          ? 'Dạ, bạn đợi Linh một chút để lên lịch trình $city nhé!'
          : 'Dạ, bạn đợi Linh một chút để thiết kế lịch trình cho bạn nhé!';
      _startFillerTts(filler);
    }

    try {
      Trip trip;

      final existingTripId = _activeTripIdFromState(effectiveCtx);

      if (existingTripId != null && existingTripId.isNotEmpty) {
        try {
          final generated = await _tripRepo.generateItineraryForTrip(
            existingTripId,

            userPrompt: userPrompt,

            saveToDb: true,

            context: effectiveCtx,
          );

          if (generated != null) {
            trip = generated;
          } else {
            trip = await _tripRepo.generateItineraryPreview(
              conversationId: cid ?? 0,

              context: effectiveCtx,

              userPrompt: userPrompt,
            );
          }
        } on TripNotFoundException {
          final fallbackContext = Map<String, dynamic>.from(effectiveCtx ?? {});

          final tripContext = fallbackContext['trip'];

          if (tripContext is Map<String, dynamic>) {
            final updatedTripContext = Map<String, dynamic>.from(tripContext)
              ..remove('trip_id');

            fallbackContext['trip'] = updatedTripContext;
          }

          state = state.copyWith(
            clearSavedTripId: true,

            clearTripPreview: true,

            planningContext: fallbackContext,
          );

          trip = await _tripRepo.generateItineraryPreview(
            conversationId: cid ?? 0,

            context: fallbackContext,

            userPrompt: userPrompt,
          );
        }
      } else {
        trip = await _tripRepo.generateItineraryPreview(
          conversationId: cid ?? 0,

          context: effectiveCtx,

          userPrompt: userPrompt,
        );
      }

      _ref.invalidate(tripsListProvider);

      if (trip.id.isNotEmpty) {
        _ref.invalidate(tripDetailProvider(trip.id));
      }

      state = state.copyWith(
        planningState: TripPlanningState.previewReady,
        tripPreview: trip,
        savedTripId: trip.id.isNotEmpty ? trip.id : state.savedTripId,
      );

      _ref.read(currentTripPreviewProvider.notifier).state = trip;

      final previewMsg =
          'Mình đã hoàn thành lịch trình ${trip.title} (${trip.daysCount} ngày, ${trip.totalStops} địa điểm)!';

      final aiMsg = ChatMessage(
        text: previewMsg,
        isUser: false,
        timestamp: DateTime.now(),
        tripItinerary: trip,
      );

      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        voiceState: VoiceState.idle,
      );

      if (_isVoiceSession) {
        _userKeepMicOn = true;
      }

      _resumeListeningIfPersistent();
    } catch (e) {
      log('generate_itinerary_error', {'error': e.toString()});

      state = state.copyWith(
        planningState: TripPlanningState.error,

        voiceState: VoiceState.idle,

        error: 'Không thể tạo lịch trình: $e',
      );
    }
  }

  Future<void> saveCurrentTrip({int? convId}) async {
    final cid = convId ?? state.conversationId;
    if (state.tripPreview == null) return;

    log('saving_trip', {
      'conversationId': cid,
      'title': state.tripPreview!.title,
    });
    state = state.copyWith(
      planningState: TripPlanningState.saving,
      voiceState: VoiceState.processing,
      error: null,
    );

    try {
      final savedId = await _tripRepo.saveTripPreview(
        trip: state.tripPreview!,
        conversationId: cid ?? 0,
      );

      // Invalidate tripsListProvider to trigger immediate refresh of trips history
      _ref.invalidate(tripsListProvider);
      if (savedId.isNotEmpty) {
        _ref.invalidate(tripDetailProvider(savedId));
      }

      final updatedPreview = state.tripPreview!.copyWith(
        id: savedId,
        status: 'CONFIRMED',
      );

      state = state.copyWith(
        planningState: TripPlanningState.saved,
        savedTripId: savedId,
        tripPreview: updatedPreview,
        voiceState: VoiceState.idle,
        error: null,
      );

      final savedMsg =
          'Mình đã lưu chuyến đi "${updatedPreview.title}" (${updatedPreview.daysCount} ngày) vào danh sách chuyến đi của bạn thành công! Bạn có thể xem lại bất cứ lúc nào trong mục Chuyến đi.';
      final aiMsg = ChatMessage(
        text: savedMsg,
        isUser: false,
        timestamp: DateTime.now(),
        tripItinerary: updatedPreview,
      );
      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        currentTranscript: savedMsg,
      );

      if (_isVoiceSession) {
        _userKeepMicOn = true;
      }

      if (state.isTtsEnabled) {
        _ttsCancelled = false;
        await _playTts(savedMsg);
      } else {
        _resumeListeningIfPersistent();
      }
    } catch (e) {
      log('save_trip_error', {'error': e.toString()});
      state = state.copyWith(
        planningState: TripPlanningState.error,
        voiceState: VoiceState.idle,
        error: 'Không thể lưu chuyến đi: $e',
      );
      if (_isVoiceSession) {
        _userKeepMicOn = true;
      }
      _resumeListeningIfPersistent();
    }
  }

  /// Chỉnh sửa chuyến đi hiện tại (hỗ trợ cả chuyến đi đã lưu có ID lẫn bản xem trước chưa có ID trên DB).
  Future<void> editCurrentOrSavedTrip({
    required String instruction,
    int? targetDay,
    Trip? fallbackTrip,
    bool rethrowOnError = false,
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return;

    String? effectiveTripId;
    if (fallbackTrip != null && _isValidPersistedTripId(fallbackTrip.id)) {
      effectiveTripId = fallbackTrip.id.trim();
      state = state.copyWith(
        tripPreview: fallbackTrip,
        savedTripId: effectiveTripId,
        planningState: fallbackTrip.status == 'CONFIRMED'
            ? TripPlanningState.saved
            : TripPlanningState.previewReady,
      );
    } else if (fallbackTrip == null ||
        (state.tripPreview != null &&
            state.tripPreview!.title == fallbackTrip.title &&
            state.tripPreview!.destination == fallbackTrip.destination)) {
      effectiveTripId = _activeTripIdFromState();
    }

    // Nếu đang có bản xem trước nhưng chưa có trip_id hợp lệ trong CSDL, tự động tạo/lưu nháp để lấy trip_id thực
    final previewCandidate = fallbackTrip ?? state.tripPreview;
    if (effectiveTripId == null && previewCandidate != null) {
      try {
        state = state.copyWith(
          planningState: TripPlanningState.revising,
          voiceState: VoiceState.processing,
          error: null,
        );
        final persistedId = await _tripRepo.saveTripPreview(
          trip: previewCandidate,
          conversationId:
              state.conversationId ?? previewCandidate.conversationId ?? 0,
        );
        if (_isValidPersistedTripId(persistedId)) {
          effectiveTripId = persistedId.trim();
          state = state.copyWith(
            savedTripId: effectiveTripId,
            tripPreview: previewCandidate.copyWith(id: effectiveTripId),
          );
        }
      } catch (e) {
        log('auto_persist_before_edit_error', {'error': e.toString()});
      }
    }

    if (effectiveTripId != null) {
      await editSavedTrip(
        tripId: effectiveTripId,
        instruction: trimmed,
        targetDay: targetDay,
        rethrowOnError: rethrowOnError,
      );
    } else {
      await sendMessage(trimmed);
    }
  }

  Future<void> editSavedTrip({
    required String tripId,
    required String instruction,
    int? targetDay,
    bool rethrowOnError = false,
  }) async {
    final wasSaved =
        state.planningState == TripPlanningState.saved ||
        state.tripPreview?.status == 'CONFIRMED';

    // Nếu người dùng bấm nút "Sửa với AI" (text UI), ghi nhận cả câu yêu cầu vào lịch sử chat để rõ ngữ cảnh
    final lastMsg = state.messages.isNotEmpty ? state.messages.last : null;
    final alreadyHasUserMsg =
        lastMsg != null &&
        lastMsg.isUser &&
        lastMsg.text.trim() == instruction.trim();
    final updatedBaseMessages = alreadyHasUserMsg
        ? state.messages
        : [
            ...state.messages,
            ChatMessage(
              text: instruction.trim(),
              isUser: true,
              timestamp: DateTime.now(),
            ),
          ];

    log('editing_trip', {
      'tripId': tripId,
      'instruction': instruction,
      'targetDay': targetDay,
    });
    state = state.copyWith(
      messages: updatedBaseMessages,
      planningState: TripPlanningState.revising,
      voiceState: VoiceState.processing,
      error: null,
    );

    if (_isVoiceSession && state.isTtsEnabled && !state.isMuted) {
      _startFillerTts('Dạ, đợi Linh cập nhật lại lịch trình theo ý bạn nhé!');
    }

    try {
      final serverRes = await _tripRepo.editItineraryRaw(
        tripId: tripId,
        instruction: instruction,
        targetDay: targetDay,
      );

      if (serverRes != null) {
        final statusStr = serverRes['status']?.toString();
        final serverMsg = serverRes['message']?.toString();
        final itineraryData = serverRes['itinerary'] is Map<String, dynamic>
            ? serverRes['itinerary'] as Map<String, dynamic>
            : null;

        if (statusStr == 'ANSWERED') {
          final answerMsg =
              serverMsg ?? 'Lịch trình hiện tại vẫn được giữ nguyên.';
          final aiMsg = ChatMessage(
            text: answerMsg,
            isUser: false,
            timestamp: DateTime.now(),
            tripItinerary: state.tripPreview,
          );
          state = state.copyWith(
            planningState: wasSaved
                ? TripPlanningState.saved
                : TripPlanningState.previewReady,
            messages: [...state.messages, aiMsg],
            currentTranscript: answerMsg,
          );
          if (_isVoiceSession) {
            _userKeepMicOn = true;
          }
          if (state.isTtsEnabled) {
            _ttsCancelled = false;
            await _playTts(answerMsg);
          } else {
            state = state.copyWith(voiceState: VoiceState.idle);
            _resumeListeningIfPersistent();
          }
          return;
        }

        if (statusStr == 'FAILED' ||
            statusStr == 'NEED_CLARIFICATION' ||
            itineraryData == null) {
          final failMsg =
              serverMsg ??
              'Mình chưa thể cập nhật lịch trình theo yêu cầu này. Bạn hãy thử nói rõ hơn ngày hoặc địa điểm muốn đổi nhé!';
          final aiMsg = ChatMessage(
            text: failMsg,
            isUser: false,
            timestamp: DateTime.now(),
            tripItinerary: state.tripPreview,
          );
          state = state.copyWith(
            planningState: state.tripPreview != null
                ? (wasSaved
                      ? TripPlanningState.saved
                      : TripPlanningState.previewReady)
                : TripPlanningState.error,
            voiceState: VoiceState.idle,
            messages: [...state.messages, aiMsg],
            currentTranscript: failMsg,
            error: failMsg,
          );
          if (rethrowOnError) {
            throw Exception(failMsg);
          }
          if (_isVoiceSession) {
            _userKeepMicOn = true;
          }
          if (state.isTtsEnabled) {
            _ttsCancelled = false;
            await _playTts(failMsg);
          } else {
            _resumeListeningIfPersistent();
          }
          return;
        }

        final updatedTrip = Trip.fromJson(itineraryData);
        final resolvedTrip =
            (updatedTrip.id.isNotEmpty
                    ? updatedTrip
                    : updatedTrip.copyWith(id: tripId))
                .copyWith(status: wasSaved ? 'CONFIRMED' : updatedTrip.status);

        _ref.invalidate(tripsListProvider);
        _ref.invalidate(tripDetailProvider(tripId));
        _ref.read(currentTripPreviewProvider.notifier).state = resolvedTrip;

        final nextPlanningState =
            (wasSaved || resolvedTrip.status == 'CONFIRMED')
            ? TripPlanningState.saved
            : TripPlanningState.previewReady;

        state = state.copyWith(
          planningState: nextPlanningState,
          tripPreview: resolvedTrip,
          savedTripId: tripId,
          error: null,
        );

        final editMsg =
            serverMsg ??
            'Đã cập nhật lịch trình theo yêu cầu: "$instruction".';
        final aiMsg = ChatMessage(
          text: editMsg,
          isUser: false,
          timestamp: DateTime.now(),
          tripItinerary: resolvedTrip,
        );
        state = state.copyWith(
          messages: [...state.messages, aiMsg],
          voiceState: VoiceState.idle,
        );

        if (_isVoiceSession) {
          _userKeepMicOn = true;
        }
        _resumeListeningIfPersistent();
      } else {
        state = state.copyWith(
          planningState: wasSaved
              ? TripPlanningState.saved
              : TripPlanningState.previewReady,
          voiceState: VoiceState.idle,
        );
      }
    } catch (e) {
      log('edit_trip_error', {'error': e.toString()});
      final cleanErr = e.toString().replaceFirst('Exception: ', '');
      final errReply = 'Chưa thể chỉnh sửa lịch trình: $cleanErr';
      final aiErrMsg = ChatMessage(
        text: errReply,
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        planningState: state.tripPreview != null
            ? (wasSaved
                  ? TripPlanningState.saved
                  : TripPlanningState.previewReady)
            : TripPlanningState.error,
        voiceState: VoiceState.idle,
        messages: [...state.messages, aiErrMsg],
        currentTranscript: errReply,
        error: errReply,
      );
      if (rethrowOnError) {
        rethrow;
      }
      if (_isVoiceSession) {
        _userKeepMicOn = true;
      }
      _resumeListeningIfPersistent();
    }
  }

  /// Trích xuất tóm tắt thông tin hành trình từ planning_context

  String? _formatPlanningContextSummary(Map<String, dynamic>? ctx) {
    if (ctx == null) return null;

    final trip = ctx['trip'] as Map<String, dynamic>?;

    if (trip == null) return null;

    final parts = <String>[];

    final destination = trip['destination'] as Map<String, dynamic>?;

    final city = destination?['city']?.toString();

    if (city != null && city.isNotEmpty) {
      parts.add('Điểm đến: $city');
    }

    final dates = trip['dates'] as Map<String, dynamic>?;

    final days = dates?['duration_days'];

    if (days != null && days is int && days > 0) {
      parts.add('$days ngày');
    }

    final travelers = trip['travelers'] as Map<String, dynamic>?;

    final adults = travelers?['adults'];

    if (adults != null && adults is int && adults > 0) {
      parts.add('$adults người lớn');
    }

    final budget = ctx['budget'] as Map<String, dynamic>?;

    final total = budget?['total'];

    if (total != null) {
      final currency = budget?['currency']?.toString() ?? 'VND';

      parts.add('Ngân sách: $total $currency');
    }

    return parts.isNotEmpty ? parts.join(' • ') : null;
  }

  // ── TTS ──────────────────────────────────────────────────────────────────

  List<String> _splitSentencesForTts(String cleaned) {
    if (cleaned.isEmpty) return const [];

    final rawParts = cleaned.split(RegExp(r'(?<=[.!?\n])\s+'));

    final sentences = <String>[];

    String current = '';

    for (final part in rawParts) {
      final p = part.trim();

      if (p.isEmpty) continue;

      if (current.isNotEmpty && (current.length + p.length) < 55) {
        current = '$current $p';
      } else {
        if (current.isNotEmpty) sentences.add(current);

        current = p;
      }
    }

    if (current.isNotEmpty) sentences.add(current);

    return sentences.isNotEmpty ? sentences : [cleaned];
  }

  /// Speaks a short non-blocking acknowledgment while a slow LLM task
  /// (itinerary generation/revision) runs in parallel, keeping voice UX snappy.
  void _startFillerTts(String text) {
    if (!mounted || state.isMuted || !state.isTtsEnabled) return;
    final clean = _cleanTextForTts(text);
    if (clean.isEmpty) return;

    prepareForTtsPlayback();
    _audioService.initStreamingQueue(
      onPlay: () {
        if (!mounted || _ttsCancelled) return;
        state = state.copyWith(voiceState: VoiceState.speaking, error: null);
      },
      onEnded: () {
        if (!mounted) return;
        if (state.planningState == TripPlanningState.generating ||
            state.planningState == TripPlanningState.revising) {
          state = state.copyWith(voiceState: VoiceState.processing);
        }
      },
      onError: (_) {
        if (!mounted) return;
        if (state.planningState == TripPlanningState.generating ||
            state.planningState == TripPlanningState.revising) {
          state = state.copyWith(voiceState: VoiceState.processing);
        }
      },
    );
    _audioService.enqueueSentence(
      baseUrl: ApiConfig.baseUrl,
      sentence: clean,
      speed: state.ttsSpeed,
      speakerId: state.speakerId,
    );
    _audioService.markStreamDone();
  }

  Future<void> _playTts(String text) async {
    if (!mounted || _ttsCancelled) return;
    if (state.isMuted || !state.isTtsEnabled) {
      state = state.copyWith(voiceState: VoiceState.idle);
      return;
    }

    prepareForTtsPlayback();
    final cleanText = _cleanTextForTts(text);
    if (cleanText.isEmpty) {
      state = state.copyWith(voiceState: VoiceState.idle);
      return;
    }

    final sentences = _splitSentencesForTts(cleanText);
    log('tts_request', {
      'textLength': cleanText.length,
      'sentenceCount': sentences.length,
    });

    final watchdogMs = (cleanText.length * 110).clamp(12000, 45000);
    try {
      _ttsSafetyTimer?.cancel();
      _ttsSafetyTimer = Timer(Duration(milliseconds: watchdogMs), () {
        if (mounted &&
            (state.voiceState == VoiceState.speaking ||
                state.voiceState == VoiceState.processing)) {
          log('tts_safety_watchdog_fired');
          _audioService.stopTts();
          _resumeListeningIfPersistent();
        }
      });

      _audioService.initStreamingQueue(
        onPlay: () {
          if (!mounted) return;
          if (_ttsCancelled) {
            _audioService.stopTts();
            return;
          }
          log('tts_playback_started');
          state = state.copyWith(voiceState: VoiceState.speaking, error: null);
        },
        onEnded: () {
          if (!mounted) return;
          _ttsSafetyTimer?.cancel();
          log('tts_playback_finished');
          if (state.planningState != TripPlanningState.generating &&
              state.planningState != TripPlanningState.revising) {
            _resumeListeningIfPersistent();
          }
        },
        onError: (err) {
          if (!mounted) return;
          _ttsSafetyTimer?.cancel();
          log('tts_playback_error', {'error': err});
          state = state.copyWith(error: 'Không thể phát audio: $err');
          _resumeListeningIfPersistent();
        },
      );

      for (final sentence in sentences) {
        if (_ttsCancelled) break;
        _audioService.enqueueSentence(
          baseUrl: ApiConfig.baseUrl,
          sentence: sentence,
          speed: _defaultTtsSpeed,
          speakerId: _defaultSpeakerId,
        );
      }

      if (!_ttsCancelled) {
        _audioService.markStreamDone();
      }
    } catch (e) {
      _ttsSafetyTimer?.cancel();
      log('tts_exception', {'error': e.toString()});
      if (mounted) {
        state = state.copyWith(
          voiceState: VoiceState.idle,
          error: 'Lỗi phát giọng nói AI: $e',
        );
      }
    }
  }

  /// Replay the last TTS audio if available, or generate TTS for text.

  Future<void> playTtsForText(String text) async {
    _audioService.stopTts();

    await _playTts(text);
  }

  /// Strips Markdown, code blocks, URLs from text before TTS.

  String _cleanTextForTts(String text) {
    var t = text;

    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    t = t.replaceAll(RegExp(r'`[^`]+`'), '');

    t = t.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');

    t = t.replaceAll(RegExp(r'https?://\S+'), '');

    t = t.replaceAll(RegExp(r'[*_~#>-]'), ' ');

    t = t.replaceAll(RegExp(r'\s+'), ' ');

    return t.trim();
  }

  @override
  void dispose() {
    _ttsSafetyTimer?.cancel();
    _resumeListenTimer?.cancel();
    _dedupeResetTimer?.cancel();
    _audioService.abortStream();
    _abortListening();
    _audioService.stopTts();
    _isVoiceSession = false;
    unawaited(
      _disconnectLiveKitAfterPendingConnect(clearConversation: false),
    );
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final voiceAssistantProvider =
    StateNotifierProvider<VoiceAssistantNotifier, VoiceAssistantState>(
      (ref) => VoiceAssistantNotifier(ref),
    );
