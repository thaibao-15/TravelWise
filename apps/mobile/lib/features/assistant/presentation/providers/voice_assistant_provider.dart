import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/voice_audio_service.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/auth_di.dart';
import '../../../trips/data/repositories/trip_repository.dart';
import '../../../trips/models/trip_model.dart';
import '../../../trips/providers/trip_provider.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum VoiceState { idle, listening, thinking, speaking, processing, connecting, error }

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

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.audioBytes,
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
    bool? isTtsEnabled,
    Uint8List? lastAudioBytes,
    Trip? tripPreview,
    String? savedTripId,
    String? planningContextSummary,
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
      conversationId: conversationId ?? this.conversationId,
      isTtsEnabled: isTtsEnabled ?? this.isTtsEnabled,
      lastAudioBytes: lastAudioBytes ?? this.lastAudioBytes,
      tripPreview: tripPreview ?? this.tripPreview,
      savedTripId: savedTripId ?? this.savedTripId,
      planningContextSummary:
          planningContextSummary ?? this.planningContextSummary,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class VoiceAssistantNotifier extends StateNotifier<VoiceAssistantState> {
  final Ref _ref;
  final VoiceAudioService _audioService = VoiceAudioService();

  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  String _lastTranscript = '';
  String? _lastSubmittedTranscript;
  bool _isCommitting = false;
  int _sessionId = 0;

  VoiceAssistantNotifier(this._ref) : super(const VoiceAssistantState());

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
        isConversationExpanded: !state.isConversationExpanded);
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
    if (state.isMuted) {
      log('mic_unmuted');
      state = state.copyWith(isMuted: false);
    } else {
      log('mic_muted');
      if (state.isRecording) {
        _stopStt();
      }
      _audioService.stopTts();
      state = state.copyWith(
        isMuted: true,
        isRecording: false,
        voiceState: VoiceState.idle,
      );
    }
  }

  void toggleRecording() {
    if (state.isRecording ||
        state.voiceState == VoiceState.connecting ||
        state.voiceState == VoiceState.listening) {
      log('user_toggle_recording_off');
      _stopStt();
      state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
    } else {
      if (state.isMuted) {
        log('record_blocked_muted');
        return;
      }
      if (_isCommitting ||
          state.voiceState == VoiceState.thinking ||
          state.voiceState == VoiceState.processing ||
          state.voiceState == VoiceState.speaking) {
        log('record_blocked_busy', {'voiceState': state.voiceState.name});
        return;
      }
      log('user_toggle_recording_on');
      _startStt();
    }
  }

  void stopAudio() {
    log('tts_stop');
    _audioService.stopTts();
    if (state.voiceState == VoiceState.speaking) {
      state = state.copyWith(voiceState: VoiceState.idle);
    }
  }

  void dismissPreview() {
    state = state.copyWith(
      planningState: TripPlanningState.idle,
      tripPreview: null,
    );
  }

  // ── STT (Web Microphone WebSocket) ───────────────────────────────────────

  void _startStt() {
    if (state.isRecording || state.voiceState == VoiceState.connecting) return;

    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _lastTranscript = '';
    _isCommitting = false;
    _audioService.stopTts();

    final sessionId = ++_sessionId;
    final baseUrl = ApiConfig.baseUrl;
    final wsProtocol = baseUrl.startsWith('https') ? 'wss:' : 'ws:';
    final wsHost =
        baseUrl.replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    final wsUrl = '$wsProtocol//$wsHost/api/v1/stt/ws';

    log('stt_start', {'wsUrl': wsUrl, 'sessionId': sessionId});

    state = state.copyWith(
      voiceState: VoiceState.connecting,
      currentTranscript: '',
      error: null,
      isRecording: false,
    );

    _audioService.startRecording(
      wsUrl: wsUrl,
      onReady: () {
        if (!mounted || sessionId != _sessionId) return;
        log('stt_ready', {'sessionId': sessionId});
        state = state.copyWith(
          voiceState: VoiceState.listening,
          isRecording: true,
          error: null,
        );
        _armNoSpeechTimer(sessionId);
      },
      onTranscript: (text, isFinal) {
        if (!mounted || sessionId != _sessionId) return;
        log('stt_transcript', {
          'isFinal': isFinal,
          'textLength': text.length,
          'sessionId': sessionId,
        });
        _handleTranscript(text, isFinal, sessionId);
      },
      onError: (err) {
        if (!mounted || sessionId != _sessionId) return;
        log('stt_error', {'error': err, 'sessionId': sessionId});
        _noSpeechTimer?.cancel();
        state = state.copyWith(
          voiceState: VoiceState.error,
          isRecording: false,
          error: 'Lỗi micro / STT: $err',
        );
      },
      onDone: () {
        if (!mounted || sessionId != _sessionId) return;
        log('stt_session_done', {
          'sessionId': sessionId,
          'wasRecording': state.isRecording,
        });
        _noSpeechTimer?.cancel();
        if (state.isRecording || state.voiceState == VoiceState.listening) {
          state = state.copyWith(
            isRecording: false,
            voiceState: VoiceState.idle,
          );
        } else if (state.voiceState == VoiceState.connecting) {
          state = state.copyWith(
            isRecording: false,
            voiceState: VoiceState.error,
            error: 'Kết nối STT đã đóng trước khi sẵn sàng.',
          );
        }
      },
    );
  }

  void _armNoSpeechTimer(int sessionId) {
    _noSpeechTimer?.cancel();
    _noSpeechTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || sessionId != _sessionId) return;
      if (_lastTranscript.trim().isNotEmpty) return;
      if (state.voiceState != VoiceState.listening) return;
      log('stt_no_speech_timeout', {'sessionId': sessionId});
      _stopStt();
      state = state.copyWith(
        isRecording: false,
        voiceState: VoiceState.error,
        error:
            'Không nhận được giọng nói. Hãy nói rõ hơn hoặc kiểm tra microphone / kết nối STT.',
      );
    });
  }

  void _handleTranscript(String text, bool isFinal, int sessionId) {
    if (sessionId != _sessionId) return;
    if (state.voiceState == VoiceState.thinking ||
        state.voiceState == VoiceState.speaking ||
        state.voiceState == VoiceState.processing) {
      return;
    }
    if (text.trim().isEmpty) return;

    _noSpeechTimer?.cancel();
    _lastTranscript = text;
    state = state.copyWith(
      currentTranscript: text,
      voiceState: VoiceState.listening,
      isRecording: true,
      error: null,
    );

    _silenceTimer?.cancel();
    final delay = isFinal ? 450 : 900;
    if (text.trim().length >= 2) {
      _silenceTimer = Timer(Duration(milliseconds: delay), () {
        if (!mounted || sessionId != _sessionId) return;
        if (_lastTranscript.isNotEmpty) {
          log('silence_commit', {
            'textLength': _lastTranscript.length,
            'isFinal': isFinal,
          });
          sendMessage(_lastTranscript, isVoiceMode: true);
        }
      });
    }
  }

  void _stopStt() {
    log('stt_stop');
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _audioService.stopRecording();
    _lastTranscript = '';
  }

  // ── Send message (RAG ask) ────────────────────────────────────────────────

  Future<void> sendMessage(String text, {bool isVoiceMode = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_isCommitting ||
        state.voiceState == VoiceState.thinking ||
        state.voiceState == VoiceState.processing) {
      log('rag_submit_skipped_busy', {'voiceState': state.voiceState.name});
      return;
    }
    if (isVoiceMode &&
        _lastSubmittedTranscript != null &&
        _lastSubmittedTranscript == trimmed) {
      log('rag_submit_skipped_duplicate', {'textLength': trimmed.length});
      return;
    }

    _isCommitting = true;
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _stopStt();
    stopAudio();
    _lastSubmittedTranscript = trimmed;

    log('rag_submit', {
      'textLength': trimmed.length,
      'conversationId': state.conversationId,
      'isVoiceMode': isVoiceMode,
    });

    final userMsg = ChatMessage(
      text: trimmed,
      isUser: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      voiceState: isVoiceMode ? VoiceState.processing : VoiceState.thinking,
      currentTranscript: trimmed,
      isRecording: false,
      error: null,
    );

    try {
      final response = await _dio.post(
        '/api/v1/rag/ask',
        data: {
          'message': trimmed,
          if (state.conversationId != null)
            'conversation_id': state.conversationId,
          'mode': isVoiceMode ? 'voice' : 'chat',
        },
      );

      if (!mounted) return;

      log('rag_response', {'statusCode': response.statusCode});

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final content =
            (data['message'] as Map<String, dynamic>)['content'] as String;
        final convId = data['conversation_id'] as int?;
        final planningStatus = data['planning_status']?.toString();
        final isReady = data['is_ready_to_generate'] == true;
        final planningAction = data['planning_action']?.toString();

        log('rag_success', {
          'contentLength': content.length,
          'conversationId': convId,
          'planningStatus': planningStatus,
          'isReady': isReady,
          'planningAction': planningAction,
        });

        final aiMsg = ChatMessage(
          text: content,
          isUser: false,
          timestamp: DateTime.now(),
        );

        TripPlanningState derivedPlanning = state.planningState;
        if (planningStatus == 'collecting_requirements') {
          derivedPlanning = TripPlanningState.collectingRequirements;
        } else if (planningStatus == 'ready_to_generate' || isReady) {
          derivedPlanning = TripPlanningState.readyToGenerate;
        }

        state = state.copyWith(
          messages: [...state.messages, aiMsg],
          conversationId: convId,
          currentTranscript: content,
          planningState: derivedPlanning,
        );

        if (isVoiceMode || state.isTtsEnabled) {
          await _playTts(content);
        } else {
          state = state.copyWith(voiceState: VoiceState.idle);
        }

        // Orchestrate automatic generation or saving based on structured backend planning_action
        if (planningAction == 'TRIGGER_GENERATION' && convId != null) {
          await generateItinerary(convId: convId);
        } else if (planningAction == 'TRIGGER_SAVE' && state.tripPreview != null && convId != null) {
          await saveCurrentTrip(convId: convId);
        }
      } else {
        state = state.copyWith(
          voiceState: VoiceState.error,
          error: 'Lỗi từ máy chủ AI (${response.statusCode})',
        );
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
      _isCommitting = false;
      // Allow a later identical utterance after this turn completes.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_lastSubmittedTranscript == trimmed) {
          _lastSubmittedTranscript = null;
        }
      });
    }
  }

  // ── Trip Planning Generation & Persistence ──────────────────────────────

  Future<void> generateItinerary({int? convId}) async {
    final cid = convId ?? state.conversationId;
    if (cid == null) return;

    log('generating_itinerary', {'conversationId': cid});
    state = state.copyWith(planningState: TripPlanningState.generating, error: null);

    try {
      final trip = await _tripRepo.generateItineraryPreview(conversationId: cid);
      state = state.copyWith(
        planningState: TripPlanningState.previewReady,
        tripPreview: trip,
      );
      _ref.read(currentTripPreviewProvider.notifier).state = trip;

      const previewMsg = 'Mình đã tạo xong lịch trình xem trước cho bạn với các địa điểm thực tế từ hệ thống! Bạn có thể xem trên bản đồ hoặc bấm Lưu chuyến đi.';
      final aiMsg = ChatMessage(
        text: previewMsg,
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        currentTranscript: previewMsg,
      );

      if (state.isTtsEnabled) {
        await _playTts(previewMsg);
      }
    } catch (e) {
      log('generate_itinerary_error', {'error': e.toString()});
      state = state.copyWith(
        planningState: TripPlanningState.error,
        error: 'Không thể tạo lịch trình: $e',
      );
    }
  }

  Future<void> saveCurrentTrip({int? convId}) async {
    final cid = convId ?? state.conversationId;
    if (state.tripPreview == null || cid == null) return;

    log('saving_trip', {'conversationId': cid, 'title': state.tripPreview!.title});
    state = state.copyWith(planningState: TripPlanningState.saving, error: null);

    try {
      final savedId = await _tripRepo.saveTripPreview(
        trip: state.tripPreview!,
        conversationId: cid,
      );

      // Invalidate tripsListProvider to trigger immediate refresh of trips history
      _ref.invalidate(tripsListProvider);

      state = state.copyWith(
        planningState: TripPlanningState.saved,
        savedTripId: savedId,
      );

      const savedMsg = 'Chuyến đi của bạn đã được lưu thành công vào cơ sở dữ liệu! Bạn có thể xem lại bất cứ lúc nào trong mục Chuyến đi.';
      final aiMsg = ChatMessage(
        text: savedMsg,
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        currentTranscript: savedMsg,
      );

      if (state.isTtsEnabled) {
        await _playTts(savedMsg);
      }
    } catch (e) {
      log('save_trip_error', {'error': e.toString()});
      state = state.copyWith(
        planningState: TripPlanningState.error,
        error: 'Không thể lưu chuyến đi: $e',
      );
    }
  }

  Future<void> editSavedTrip({
    required String tripId,
    required String instruction,
  }) async {
    log('editing_trip', {'tripId': tripId, 'instruction': instruction});
    state = state.copyWith(planningState: TripPlanningState.revising, error: null);

    try {
      final updatedTrip = await _tripRepo.editItinerary(
        tripId: tripId,
        instruction: instruction,
      );

      if (updatedTrip != null) {
        _ref.invalidate(tripsListProvider);
        _ref.invalidate(tripDetailProvider(tripId));

        state = state.copyWith(
          planningState: TripPlanningState.saved,
          tripPreview: updatedTrip,
        );

        final editMsg = 'Đã cập nhật lịch trình theo yêu cầu của bạn: "$instruction".';
        final aiMsg = ChatMessage(
          text: editMsg,
          isUser: false,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(
          messages: [...state.messages, aiMsg],
          currentTranscript: editMsg,
        );

        if (state.isTtsEnabled) {
          await _playTts(editMsg);
        }
      }
    } catch (e) {
      log('edit_trip_error', {'error': e.toString()});
      state = state.copyWith(
        planningState: TripPlanningState.error,
        error: 'Không thể chỉnh sửa lịch trình: $e',
      );
    }
  }

  // ── TTS ──────────────────────────────────────────────────────────────────

  Future<void> _playTts(String text) async {
    if (!mounted) return;
    final cleanText = _cleanTextForTts(text);
    if (cleanText.isEmpty) {
      state = state.copyWith(voiceState: VoiceState.idle);
      return;
    }

    log('tts_request', {'textLength': cleanText.length});

    try {
      final response = await _dio.post(
        '/api/v1/tts',
        data: {
          'text': cleanText,
          'speaker_id': 'HN-Nam-1-BL',
          'speed': '1',
        },
        options: Options(responseType: ResponseType.bytes),
      );

      if (!mounted) return;

      final contentType = response.headers.value('content-type');
      final bytes = response.data as Uint8List;
      log('tts_response', {
        'statusCode': response.statusCode,
        'contentType': contentType,
        'bytes': bytes.length,
      });

      if (response.statusCode == 200 && bytes.isNotEmpty) {
        state = state.copyWith(lastAudioBytes: bytes);

        _audioService.playWavBytes(
          bytes,
          onPlay: () {
            if (!mounted) return;
            log('tts_playback_started');
            state = state.copyWith(
              voiceState: VoiceState.speaking,
              error: null,
            );
          },
          onEnded: () {
            if (!mounted) return;
            log('tts_playback_finished');
            state = state.copyWith(voiceState: VoiceState.idle);
          },
          onError: (err) {
            if (!mounted) return;
            log('tts_playback_error', {'error': err});
            state = state.copyWith(
              voiceState: VoiceState.idle,
              error: 'Không thể phát audio: $err',
            );
          },
        );
      } else {
        state = state.copyWith(voiceState: VoiceState.idle);
      }
    } catch (e) {
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
    _silenceTimer?.cancel();
    _noSpeechTimer?.cancel();
    _stopStt();
    _audioService.stopTts();
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final voiceAssistantProvider =
    StateNotifierProvider<VoiceAssistantNotifier, VoiceAssistantState>(
  (ref) => VoiceAssistantNotifier(ref),
);
