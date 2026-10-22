import 'dart:async';
import 'dart:convert';
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
  final Trip? tripItinerary;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.audioBytes,
    this.tripItinerary,
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
    bool clearTripPreview = false,
    String? savedTripId,
    bool clearSavedTripId = false,
    String? planningContextSummary,
    Map<String, dynamic>? planningContext,
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
      tripPreview: clearTripPreview ? null : (tripPreview ?? this.tripPreview),
      savedTripId: clearSavedTripId ? null : (savedTripId ?? this.savedTripId),
      planningContextSummary:
          planningContextSummary ?? this.planningContextSummary,
      planningContext: planningContext ?? this.planningContext,
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

  /// Maximum length of one listening turn.
  final Duration listenFor;

  /// Give up if nothing at all is recognised within this window.
  final Duration noSpeechTimeout;

  /// How many times a recognizer that closes unexpectedly may be reopened
  /// within a single listening turn.
  final int maxAutoRestarts;

  const VoiceListeningConfig({
    this.pauseFor = const Duration(milliseconds: 1100),
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

  Timer? _silenceTimer;
  Timer? _noSpeechTimer;
  Timer? _maxSessionTimer;
  String? _lastSubmittedTranscript;
  bool _isCommitting = false;

  /// Id of the current recognizer connection; stale callbacks are dropped.
  int _sessionId = 0;

  /// True while the user wants the mic open (spans recognizer restarts).
  bool _listeningTurnActive = false;
  int _autoRestarts = 0;
  DateTime? _turnStartedAt;

  /// Finalised transcript segments of the current turn + the live partial.
  final List<String> _finalSegments = [];
  String _partialSegment = '';

  VoiceAssistantNotifier(
    this._ref, {
    VoiceAudioService? audioService,
    VoiceListeningConfig config = const VoiceListeningConfig(),
  })  : _audioService = audioService ?? VoiceAudioService(),
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
      _abortListening();
      _audioService.stopTts();
      state = state.copyWith(
        isMuted: true,
        isRecording: false,
        voiceState: VoiceState.idle,
      );
    }
  }

  void toggleRecording() {
    if (_listeningTurnActive ||
        state.isRecording ||
        state.voiceState == VoiceState.connecting ||
        state.voiceState == VoiceState.listening) {
      log('user_toggle_recording_off');
      // Manual stop: submit what was said so far, never auto-restart.
      _finishListening(reason: 'manual_stop', submit: true);
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
      _beginListening();
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
      clearTripPreview: true,
    );
  }

  /// Cancels an active listening turn without submitting (e.g. user left the
  /// assistant tab).
  void cancelListening() {
    if (!_listeningTurnActive && !state.isRecording) return;
    log('stt_cancel');
    _abortListening();
    state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
  }

  /// Must run before any TTS playback so the AI never hears itself.
  void prepareForTtsPlayback() {
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
    _listeningTurnActive = true;
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

  void _openRecognizer() {
    final sessionId = ++_sessionId;
    final baseUrl = ApiConfig.baseUrl;
    final wsProtocol = baseUrl.startsWith('https') ? 'wss:' : 'ws:';
    final wsHost =
        baseUrl.replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
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

    final neverConnected = state.voiceState == VoiceState.connecting &&
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
        error:
            'Không nhận được giọng nói. Hãy nói rõ hơn hoặc kiểm tra microphone / kết nối STT.',
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
    // When STT sends a final segment (isFinal == true), use a faster 800ms window.
    _silenceTimer?.cancel();
    final waitDuration = isFinal
        ? const Duration(milliseconds: 800)
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
    final text = _accumulatedTranscript;
    log('stt_finish', {'reason': reason, 'textLength': text.length});
    _abortListening();
    if (submit && text.isNotEmpty) {
      sendMessage(text, isVoiceMode: true);
    } else {
      state = state.copyWith(isRecording: false, voiceState: VoiceState.idle);
    }
  }

  /// Stops the recognizer, invalidates pending callbacks and disables any
  /// automatic restart. Does not touch [state].
  void _abortListening() {
    _listeningTurnActive = false;
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
    const vietnamese = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const nonVietnamese = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
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

    final hasActionVerb = RegExp(
          r'(?:hãy\s+)?(?:tạo|lên|lập|thiết\s*kế|xây\s*dựng|gợi\s*ý|chuẩn\s*bị|làm|viết|sắp\s*xếp|cho\s*(?:mình|tôi|em|anh|chị))',
          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:hay\s+)?(?:tao|len|lap|thiet\s*ke|xay\s*dung|goi\s*y|chuan\s*bi|lam|viet|sap\s*xep|cho\s*(?:minh|toi|em|anh|chi))',
          caseSensitive: false,
        ).hasMatch(noAccent);

    final hasTargetNoun = RegExp(
          r'(?:lịch\s*trình|kế\s*hoạch|lộ\s*trình|tour|chuyến\s*đi)',
          caseSensitive: false,
        ).hasMatch(clean) ||
        RegExp(
          r'(?:lich\s*trinh|ke\s*hoach|lo\s*trinh|tour|chuyen\s*di)',
          caseSensitive: false,
        ).hasMatch(noAccent);

    if (hasActionVerb && hasTargetNoun) return true;

    if (RegExp(r'(?:tạo|lên|lập)\s*lịch\b', caseSensitive: false).hasMatch(clean) ||
        RegExp(r'(?:tao|len|lap)\s*lich\b', caseSensitive: false).hasMatch(noAccent)) {
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
        (country != null && country.isNotEmpty && country.toLowerCase() != 'việt nam') ||
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

  String? _activeTripIdFromState([Map<String, dynamic>? ctx]) {
    if (state.savedTripId != null && state.savedTripId!.isNotEmpty) {
      return state.savedTripId;
    }
    if (state.tripPreview != null && state.tripPreview!.id.isNotEmpty) {
      return state.tripPreview!.id;
    }
    final c = ctx ?? state.planningContext;
    final tripMap = c?['trip'] as Map<String, dynamic>?;
    final tid = tripMap?['trip_id']?.toString();
    if (tid != null && tid.isNotEmpty) return tid;
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
    final dayMatch = RegExp(r'(\d+)\s*ngày', caseSensitive: false).firstMatch(lower) ??
        RegExp(r'(\d+)\s*ngay', caseSensitive: false).firstMatch(_removeVietnameseAccents(lower));
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

    existingTrip['destination'] = {
      'city': matchedCity,
      'country': 'Việt Nam',
    };
    existingTrip['dates'] = {
      'duration_days': durationDays,
    };
    existing['trip'] = existingTrip;
    existing['planning_state'] = {
      'is_ready_to_generate': true,
    };
    return existing;
  }

  /// Kiểm tra nhanh câu nói có khả năng là lệnh chỉnh sửa lịch trình hay không
  /// (giúp câu hỏi thông thường bỏ qua lời gọi LLM `/detect-intent` tốn 2-3 giây).
  bool _looksLikePotentialEditRequest(String text) {
    final lower = text.toLowerCase();
    final noAccent = _removeVietnameseAccents(lower);
    final hasEditCue = RegExp(
          r'(?:thêm|bớt|xóa|xoá|bỏ|đổi|thay|sửa|dời|chuyển|cập\s*nhật|chỉnh|sắp\s*xếp|rút\s*gọn|kéo\s*dài|bắt\s*đầu|kết\s*thúc|lúc\s*\d|ngày\s*\d|buổi\s*(?:sáng|trưa|chiều|tối)|thay\s*vì|không\s*muốn\s*đi|ghé\s*thêm|cho\s*thêm)',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(
          r'(?:them|bot|xoa|bo|doi|thay|sua|doi|chuyen|cap\s*nhat|chinh|sap\s*xep|rut\s*gon|keo\s*dai|bat\s*dau|ket\s*thuc|luc\s*\d|ngay\s*\d|buoi\s*(?:sang|trua|chieu|toi))',
          caseSensitive: false,
        ).hasMatch(noAccent);
    return hasEditCue;
  }

  // ── Send message (RAG ask + Web useChat.ts Itinerary Flow) ───────────────

  Future<void> sendMessage(String text, {bool isVoiceMode = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
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

    _isCommitting = true;
    _abortListening();
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
      final ctx = state.planningContext;
      final hasDestination = _hasDestinationInContext(ctx);
      final hasDuration = _hasDurationInContext(ctx);
      final isReadyToGenerate = _isReadyInContext(ctx) ||
          state.planningState == TripPlanningState.readyToGenerate;

      final isCreateCmd = isCreateItineraryCommand(trimmed);
      final isAffirmative = isCreateCmd ||
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
      final isClearIntent = RegExp(
            r'(?:xóa|xoá|hủy|bỏ|reset|clear)\s+(?:lịch\s*trình|kế\s*hoạch)(?:\s+(?:này|hiện\s*tại|đi|giúp\s*mình|hộ\s*mình))?',
            caseSensitive: false,
          ).hasMatch(trimmed) &&
          !RegExp(r'(?:thêm|sửa|đổi|ngày\s*\d)', caseSensitive: false)
              .hasMatch(trimmed);

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
      final isRegenerateIntent = RegExp(
            r'(?:tạo\s*lại|làm\s*lại|lên\s*lại|thiết\s*kế\s*lại)\s+(?:lịch\s*trình|kế\s*hoạch)(?:\s+(?:khác|mới|đi|cho\s*mình|giúp\s*mình))?',
            caseSensitive: false,
          ).hasMatch(trimmed) ||
          RegExp(
            r'(?:tạo|lên|làm)\s+(?:lịch\s*trình|kế\s*hoạch)\s+khác',
            caseSensitive: false,
          ).hasMatch(trimmed);

      if (isRegenerateIntent && hasDestination && state.conversationId != null) {
        state = state.copyWith(clearTripPreview: true);
        await generateItinerary(
          convId: state.conversationId,
          userPrompt: 'Tạo lại lịch trình khác với các địa điểm và hoạt động mới mẻ hơn',
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

      // 4. Tự động xác định ý định CHỈNH SỬA LỊCH TRÌNH (Fast-path: Gọi thẳng /itinerary/edit khi có dấu hiệu sửa,
      //    bỏ qua bước gọi trùng lặp /detect-intent vì /itinerary/edit đã tự kiểm tra intent và trả ANSWERED nếu là câu hỏi)
      final activeTripId = _activeTripIdFromState();
      if (activeTripId != null &&
          state.tripPreview != null &&
          !isCreateCmd &&
          _looksLikePotentialEditRequest(trimmed)) {
        await editSavedTrip(
          tripId: activeTripId,
          instruction: trimmed,
        );
        return;
      }

      // 5. Hỏi đáp AI siêu tốc qua SSE Streaming (/api/v1/rag/ask-stream) kết hợp phát giọng nói từng câu tức thì
      final shouldSpeak = isVoiceMode || state.isTtsEnabled;
      final streamHandled = await _askRagStream(
        trimmed,
        isVoiceMode: isVoiceMode,
        shouldSpeak: shouldSpeak,
        isCreateCmd: isCreateCmd,
        isAffirmative: isAffirmative,
        isRegenerateIntent: isRegenerateIntent,
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

        final aiMsg = ChatMessage(
          text: content,
          isUser: false,
          timestamp: DateTime.now(),
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

        state = state.copyWith(
          messages: [...state.messages, aiMsg],
          conversationId: convId,
          currentTranscript: content,
          planningState: derivedPlanning,
          planningContext: planningCtx,
          savedTripId: (ctxTripId != null && ctxTripId.isNotEmpty)
              ? ctxTripId
              : state.savedTripId,
        );

        final shouldAutoGenerate = convId != null &&
            (planningAction == 'TRIGGER_GENERATION' ||
                ((isCreateCmd || isAffirmative || isRegenerateIntent) &&
                    (derivedPlanning == TripPlanningState.readyToGenerate ||
                        hasDestAfterAsk)));

        if (shouldAutoGenerate) {
          // Tự động sinh lịch trình ngay và phát giọng đọc thông báo kết quả lịch trình
          await generateItinerary(
            convId: convId,
            context: planningCtx,
            userPrompt: trimmed,
          );
        } else if (planningAction == 'TRIGGER_SAVE' &&
            state.tripPreview != null &&
            convId != null) {
          await saveCurrentTrip(convId: convId);
        } else {
          if (isVoiceMode || state.isTtsEnabled) {
            await _playTts(content);
          } else {
            state = state.copyWith(voiceState: VoiceState.idle);
          }
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
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_lastSubmittedTranscript == trimmed) {
          _lastSubmittedTranscript = null;
        }
      });
    }
  }

  // ── SSE Streaming RAG + Realtime Sentence TTS Queue ─────────────────────

  /// Gọi `/api/v1/rag/ask-stream` để stream từng token câu trả lời thời gian thực
  /// và đẩy từng câu vào hàng đợi âm thanh (`StreamingTTSQueue`) ngay khi câu kết thúc.
  Future<bool> _askRagStream(
    String trimmed, {
    required bool isVoiceMode,
    required bool shouldSpeak,
    required bool isCreateCmd,
    required bool isAffirmative,
    required bool isRegenerateIntent,
  }) async {
    try {
      final response = await _dio.post<ResponseBody>(
        '/api/v1/rag/ask-stream',
        data: {
          'message': trimmed,
          if (state.conversationId != null)
            'conversation_id': state.conversationId,
          // Luôn gửi mode 'voice' trên luồng stream để backend bỏ qua bước contextualize LLM (tiết kiệm 2s)
          'mode': 'voice',
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return false;
      }

      if (shouldSpeak) {
        prepareForTtsPlayback();
        _audioService.initStreamingQueue(
          onPlay: () {
            if (!mounted) return;
            log('tts_stream_playback_started');
            state = state.copyWith(
              voiceState: VoiceState.speaking,
              error: null,
            );
          },
          onEnded: () {
            if (!mounted) return;
            log('tts_stream_playback_finished');
            if (state.planningState != TripPlanningState.generating &&
                state.planningState != TripPlanningState.revising) {
              state = state.copyWith(voiceState: VoiceState.idle);
            }
          },
          onError: (err) {
            if (!mounted) return;
            log('tts_stream_playback_error', {'error': err});
            if (state.planningState != TripPlanningState.generating &&
                state.planningState != TripPlanningState.revising) {
              state = state.copyWith(voiceState: VoiceState.idle);
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
      bool enqueuedAnySentence = false;

      final stream = response.data!.stream;
      await for (final chunk in stream) {
        if (!mounted) return true;
        sseBuffer += utf8.decode(chunk, allowMalformed: true);

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
          } else if (type == 'token') {
            final token = eventData['token']?.toString() ?? '';
            if (token.isEmpty) continue;

            accumulatedText += token;
            final streamingMsg = ChatMessage(
              text: accumulatedText,
              isUser: false,
              timestamp: DateTime.now(),
            );
            state = state.copyWith(
              messages: [...baseMessages, streamingMsg],
              currentTranscript: accumulatedText,
            );

            if (shouldSpeak) {
              sentenceBuffer += token;
              final match =
                  RegExp(r'^(.*?[.!?\n])(\s+|$)').firstMatch(sentenceBuffer);
              if (match != null) {
                final candidate = (match.group(1) ?? '').trim();
                if (candidate.length >= 6) {
                  final cleanedSentence = _cleanTextForTts(candidate);
                  if (cleanedSentence.isNotEmpty) {
                    enqueuedAnySentence = true;
                    _audioService.enqueueSentence(
                      baseUrl: ApiConfig.baseUrl,
                      sentence: cleanedSentence,
                      speed: '1.25',
                    );
                  }
                  sentenceBuffer =
                      sentenceBuffer.substring(match.group(0)!.length);
                }
              }
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
          } else if (type == 'error') {
            throw Exception(
                eventData['message']?.toString() ?? 'Lỗi tạo câu trả lời');
          }
        }
      }

      if (accumulatedText.trim().isEmpty) {
        return false;
      }

      if (shouldSpeak && sentenceBuffer.trim().isNotEmpty) {
        final cleanedTail = _cleanTextForTts(sentenceBuffer.trim());
        if (cleanedTail.isNotEmpty) {
          enqueuedAnySentence = true;
          _audioService.enqueueSentence(
            baseUrl: ApiConfig.baseUrl,
            sentence: cleanedTail,
            speed: '1.25',
          );
        }
        sentenceBuffer = '';
      }

      final finalMsg = ChatMessage(
        text: accumulatedText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      final isReadyFromCtx = _isReadyInContext(planningCtx);
      final hasDestAfterAsk = _hasDestinationInContext(planningCtx);
      String? ctxTripId;
      if (planningCtx != null) {
        final tripMap = planningCtx['trip'] as Map<String, dynamic>?;
        ctxTripId = tripMap?['trip_id']?.toString();
      }

      TripPlanningState derivedPlanning = state.planningState;
      if (isReadyFromCtx || hasDestAfterAsk) {
        derivedPlanning = TripPlanningState.readyToGenerate;
      }

      state = state.copyWith(
        messages: [...baseMessages, finalMsg],
        conversationId: convId,
        currentTranscript: accumulatedText,
        planningState: derivedPlanning,
        planningContext: planningCtx,
        savedTripId: (ctxTripId != null && ctxTripId.isNotEmpty)
            ? ctxTripId
            : state.savedTripId,
      );

      final shouldAutoGenerate = convId != null &&
          (isCreateCmd || isAffirmative || isRegenerateIntent) &&
          (derivedPlanning == TripPlanningState.readyToGenerate ||
              hasDestAfterAsk);

      if (shouldAutoGenerate) {
        _audioService.stopTts();
        await generateItinerary(
          convId: convId,
          context: planningCtx,
          userPrompt: trimmed,
        );
      } else if (shouldSpeak) {
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
  Future<void> requestGenerateItinerary({int? convId, String? userPrompt}) async {
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

    try {
      Trip trip;
      final existingTripId = _activeTripIdFromState(effectiveCtx);

      if (existingTripId != null && existingTripId.isNotEmpty) {
        final generated = await _tripRepo.generateItineraryForTrip(
          existingTripId,
          userPrompt: userPrompt,
          saveToDb: true,
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
          'Mình đã hoàn thành lịch trình ${trip.title} (${trip.daysCount} ngày, ${trip.totalStops} địa điểm)! Bạn có thể xem chi tiết ngay bên dưới hoặc nói yêu cầu để mình chỉnh sửa lịch trình nhé.';
      final aiMsg = ChatMessage(
        text: previewMsg,
        isUser: false,
        timestamp: DateTime.now(),
        tripItinerary: trip,
      );
      state = state.copyWith(
        messages: [...state.messages, aiMsg],
        currentTranscript: previewMsg,
      );

      if (state.isTtsEnabled) {
        await _playTts(previewMsg);
      } else {
        state = state.copyWith(voiceState: VoiceState.idle);
      }
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
      if (savedId.isNotEmpty) {
        _ref.invalidate(tripDetailProvider(savedId));
      }

      final updatedPreview =
          state.tripPreview!.copyWith(id: savedId, status: 'CONFIRMED');

      state = state.copyWith(
        planningState: TripPlanningState.saved,
        savedTripId: savedId,
        tripPreview: updatedPreview,
      );

      const savedMsg =
          'Chuyến đi của bạn đã được lưu thành công vào cơ sở dữ liệu! Bạn có thể xem lại bất cứ lúc nào trong mục Chuyến đi.';
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
    int? targetDay,
  }) async {
    log('editing_trip', {'tripId': tripId, 'instruction': instruction});
    state = state.copyWith(
      planningState: TripPlanningState.revising,
      voiceState: VoiceState.processing,
      error: null,
    );

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
            : serverRes;

        if (statusStr == 'ANSWERED') {
          // LLM & RAG nhận định đây là câu hỏi tham khảo và trả lời trực tiếp
          final answerMsg =
              serverMsg ?? 'Lịch trình hiện tại vẫn được giữ nguyên.';
          final aiMsg = ChatMessage(
            text: answerMsg,
            isUser: false,
            timestamp: DateTime.now(),
            tripItinerary: state.tripPreview,
          );
          state = state.copyWith(
            planningState: state.savedTripId != null
                ? TripPlanningState.saved
                : TripPlanningState.previewReady,
            messages: [...state.messages, aiMsg],
            currentTranscript: answerMsg,
          );
          if (state.isTtsEnabled) {
            await _playTts(answerMsg);
          } else {
            state = state.copyWith(voiceState: VoiceState.idle);
          }
          return;
        }

        final updatedTrip = Trip.fromJson(itineraryData);
        final resolvedTrip = updatedTrip.id.isNotEmpty
            ? updatedTrip
            : updatedTrip.copyWith(id: tripId);

        _ref.invalidate(tripsListProvider);
        _ref.invalidate(tripDetailProvider(tripId));
        _ref.read(currentTripPreviewProvider.notifier).state = resolvedTrip;

        state = state.copyWith(
          planningState: TripPlanningState.previewReady,
          tripPreview: resolvedTrip,
          savedTripId: tripId,
        );

        final editMsg = serverMsg ??
            'Đã cập nhật lịch trình theo yêu cầu của bạn: "$instruction".';
        final aiMsg = ChatMessage(
          text: editMsg,
          isUser: false,
          timestamp: DateTime.now(),
          tripItinerary: resolvedTrip,
        );
        state = state.copyWith(
          messages: [...state.messages, aiMsg],
          currentTranscript: editMsg,
        );

        if (state.isTtsEnabled) {
          await _playTts(editMsg);
        } else {
          state = state.copyWith(voiceState: VoiceState.idle);
        }
      } else {
        state = state.copyWith(
          planningState: TripPlanningState.previewReady,
          voiceState: VoiceState.idle,
        );
      }
    } catch (e) {
      log('edit_trip_error', {'error': e.toString()});
      state = state.copyWith(
        planningState: TripPlanningState.error,
        voiceState: VoiceState.idle,
        error: 'Không thể chỉnh sửa lịch trình: $e',
      );
    }
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

  Future<void> _playTts(String text) async {
    if (!mounted) return;
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

    try {
      _audioService.initStreamingQueue(
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

      for (final sentence in sentences) {
        _audioService.enqueueSentence(
          baseUrl: ApiConfig.baseUrl,
          sentence: sentence,
          speed: '1.25',
          speakerId: 'HN-Nam-1-BL',
        );
      }
      _audioService.markStreamDone();
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
    _abortListening();
    _audioService.stopTts();
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final voiceAssistantProvider =
    StateNotifierProvider<VoiceAssistantNotifier, VoiceAssistantState>(
  (ref) => VoiceAssistantNotifier(ref),
);
