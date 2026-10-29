import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/audio/voice_audio_service.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/auth_di.dart';
import 'package:mobile/features/assistant/presentation/models/chat_media.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/trips/models/trip_model.dart';

/// Fake recognizer: records calls and lets tests drive STT callbacks.
class FakeVoiceAudioService implements VoiceAudioService {
  @override
  void unlockAudio() {}
  int startCount = 0;
  int stopCount = 0;
  int ttsStopCount = 0;

  void Function()? _onReady;
  void Function(String text, bool isFinal)? _onTranscript;
  void Function(String err)? _onError;
  void Function()? _onDone;

  @override
  void startRecording({
    required String wsUrl,
    void Function()? onReady,
    void Function(String text, bool isFinal)? onTranscript,
    void Function(String err)? onError,
    void Function()? onDone,
  }) {
    startCount++;
    _onReady = onReady;
    _onTranscript = onTranscript;
    _onError = onError;
    _onDone = onDone;
  }

  @override
  void stopRecording() => stopCount++;

  @override
  void stopTts() => ttsStopCount++;

  void Function()? _onQueuePlay;
  void Function()? _onQueueEnded;

  @override
  void initStreamingQueue({
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {
    _onQueuePlay = onPlay;
    _onQueueEnded = onEnded;
  }

  void finishQueuePlayback() {
    _onQueuePlay?.call();
    _onQueueEnded?.call();
  }

  final List<String> enqueuedSentences = [];
  int markStreamDoneCount = 0;
  int abortStreamCount = 0;
  StreamController<String>? sseController;

  @override
  void enqueueSentence({
    required String baseUrl,
    required String sentence,
    String speed = '1.5',
    String speakerId = 'DaNang-Nu-1-BL',
  }) {
    enqueuedSentences.add(sentence);
  }

  @override
  void markStreamDone() {
    markStreamDoneCount++;
  }

  @override
  void abortStream() {
    abortStreamCount++;
    sseController?.close();
  }

  @override
  Stream<String> askStream({
    required String url,
    String? token,
    required String bodyJson,
  }) {
    final controller = sseController;
    if (controller != null) return controller.stream;
    return const Stream<String>.empty();
  }

  @override
  void playWavBytes(
    Uint8List bytes, {
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {}

  void ready() => _onReady?.call();
  void say(String text, {bool isFinal = false}) =>
      _onTranscript?.call(text, isFinal);
  void fail(String err) => _onError?.call(err);
  void done() => _onDone?.call();
}

/// Captures submissions instead of calling the backend.
class _TestNotifier extends VoiceAssistantNotifier {
  _TestNotifier(super.ref, FakeVoiceAudioService audio)
    : super(audioService: audio, config: _config);

  static const _config = VoiceListeningConfig(
    pauseFor: Duration(milliseconds: 3500),
    listenFor: Duration(seconds: 120),
    noSpeechTimeout: Duration(seconds: 10),
    maxAutoRestarts: 2,
  );

  final List<String> submitted = [];

  @override
  Future<void> sendMessage(
    String text, {
    bool isVoiceMode = false,
    List<ChatMedia> media = const [],
  }) async {
    submitted.add(text);
    state = state.copyWith(
      voiceState: VoiceState.processing,
      isRecording: false,
      currentTranscript: text,
    );
  }

  final List<({String instruction, String? tripId, int? targetDay})>
  directTripEdits = [];

  @override
  Future<void> editCurrentOrSavedTrip({
    required String instruction,
    int? targetDay,
    Trip? fallbackTrip,
    bool rethrowOnError = false,
  }) async {
    directTripEdits.add((
      instruction: instruction,
      tripId: fallbackTrip?.id,
      targetDay: targetDay,
    ));
    state = state.copyWith(
      planningState: TripPlanningState.saved,
      voiceState: VoiceState.idle,
      isRecording: false,
      currentTranscript: instruction,
    );
  }
}

typedef _Harness = ({
  ProviderContainer container,
  _TestNotifier notifier,
  FakeVoiceAudioService audio,
});

_Harness _setup() {
  final audio = FakeVoiceAudioService();
  late _TestNotifier notifier;
  final provider = StateNotifierProvider<_TestNotifier, VoiceAssistantState>((
    ref,
  ) {
    notifier = _TestNotifier(ref, audio);
    return notifier;
  });
  final container = ProviderContainer();
  container.read(provider);
  return (container: container, notifier: notifier, audio: audio);
}

class _FakeSecureStorageService implements SecureStorageService {
  @override
  Future<String?> getToken() async => 'test-jwt-token';

  @override
  Future<String?> getTokenType() async => 'bearer';

  @override
  Future<bool> hasToken() async => true;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> saveTokenType(String tokenType) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<String?> read(String key) async => null;
}

class _StreamingTestNotifier extends VoiceAssistantNotifier {
  _StreamingTestNotifier(super.ref, FakeVoiceAudioService audio)
    : super(
        audioService: audio,
        config: const VoiceListeningConfig(
          pauseFor: Duration(milliseconds: 1200),
          finalPauseFor: Duration(milliseconds: 650),
        ),
      );

  @override
  bool get useNativeFetchStream => true;
}

void main() {
  // testWidgets gives us a FakeAsync zone, so Timers advance with pump().
  testWidgets('short sentence is submitted after the silence threshold', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    expect(h.notifier.state.voiceState, VoiceState.listening);

    h.audio.say('xin chào', isFinal: true);
    await tester.pump(const Duration(milliseconds: 3000));
    expect(h.notifier.submitted, isEmpty, reason: 'still inside pause window');

    await tester.pump(const Duration(milliseconds: 600));
    expect(h.notifier.submitted, ['xin chào']);
    expect(h.audio.stopCount, greaterThan(0));
    h.container.dispose();
  });

  testWidgets('long sentence across many segments is accumulated in order', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();

    h.audio.say('tôi muốn đi');
    await tester.pump(const Duration(milliseconds: 800));
    h.audio.say('tôi muốn đi Đà Nẵng', isFinal: true);
    await tester.pump(const Duration(milliseconds: 800));
    h.audio.say('ba ngày');
    await tester.pump(const Duration(milliseconds: 800));
    h.audio.say('ba ngày hai đêm', isFinal: true);
    await tester.pump(const Duration(milliseconds: 800));
    h.audio.say('với ngân sách mười triệu', isFinal: true);

    expect(
      h.notifier.state.currentTranscript,
      'tôi muốn đi Đà Nẵng ba ngày hai đêm với ngân sách mười triệu',
    );
    expect(h.notifier.submitted, isEmpty);

    await tester.pump(const Duration(seconds: 4));
    expect(h.notifier.submitted, [
      'tôi muốn đi Đà Nẵng ba ngày hai đêm với ngân sách mười triệu',
    ]);
    h.container.dispose();
  });

  testWidgets('brief pause then resume keeps listening (old 0.9s bug)', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();

    h.audio.say('lên lịch trình');
    await tester.pump(const Duration(milliseconds: 2000)); // natural pause
    expect(h.notifier.submitted, isEmpty);
    expect(h.notifier.state.isRecording, isTrue);

    h.audio.say('lên lịch trình đi Huế', isFinal: true);
    await tester.pump(const Duration(milliseconds: 2000));
    expect(h.notifier.submitted, isEmpty);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(h.notifier.submitted, ['lên lịch trình đi Huế']);
    h.container.dispose();
  });

  testWidgets('cumulative finals and duplicate finals are not duplicated', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.say('một hai', isFinal: true);
    h.audio.say('một hai', isFinal: true); // duplicate
    h.audio.say('một hai ba bốn', isFinal: true); // cumulative resend
    h.audio.say('', isFinal: false); // empty partial must not wipe
    expect(h.notifier.state.currentTranscript, 'một hai ba bốn');
    await tester.pump(const Duration(seconds: 4));
    expect(h.notifier.submitted, ['một hai ba bốn']);
    h.container.dispose();
  });

  testWidgets('silence with no speech stops with a no-speech error', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    await tester.pump(const Duration(seconds: 11));
    expect(h.notifier.submitted, isEmpty);
    expect(h.notifier.state.voiceState, VoiceState.error);
    expect(h.notifier.state.isRecording, isFalse);
    h.container.dispose();
  });

  testWidgets('manual stop submits current text and cancels timers/restart', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.say('gợi ý quán cà phê');
    h.notifier.toggleRecording(); // manual stop
    expect(h.notifier.submitted, ['gợi ý quán cà phê']);

    final starts = h.audio.startCount;
    h.audio.done(); // late close from the stopped session
    await tester.pump(const Duration(seconds: 10));
    expect(
      h.audio.startCount,
      starts,
      reason: 'no auto restart after manual stop',
    );
    expect(h.notifier.submitted.length, 1);
    h.container.dispose();
  });

  testWidgets('manual stop with nothing said returns to idle', (tester) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.notifier.toggleRecording();
    expect(h.notifier.submitted, isEmpty);
    expect(h.notifier.state.voiceState, VoiceState.idle);
    h.container.dispose();
  });

  testWidgets('STT error without text shows error; with text submits it', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.fail('ws closed');
    expect(h.notifier.state.voiceState, VoiceState.error);
    expect(h.notifier.submitted, isEmpty);

    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.say('đi Sapa', isFinal: true);
    h.audio.fail('ws closed');
    expect(h.notifier.submitted, ['đi Sapa']);
    h.container.dispose();
  });

  testWidgets(
    'recognizer ending unexpectedly restarts (bounded) and keeps text',
    (tester) async {
      final h = _setup();
      h.notifier.toggleRecording();
      h.audio.ready();
      h.audio.say('tôi muốn đặt'); // partial in flight when session closes
      h.audio.done();
      expect(h.audio.startCount, 2, reason: 'restarted once');
      h.audio.ready();
      h.audio.say('khách sạn', isFinal: true);
      expect(h.notifier.state.currentTranscript, 'tôi muốn đặt khách sạn');

      // Further unexpected closes are bounded by maxAutoRestarts (2).
      h.audio.done();
      expect(h.audio.startCount, 3);
      h.audio.done();
      expect(h.audio.startCount, 3, reason: 'no infinite restart');
      expect(h.notifier.submitted, ['tôi muốn đặt khách sạn']);
      h.container.dispose();
    },
  );

  testWidgets('TTS start stops the microphone and ignores late transcripts', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.say('đang nói');
    final stops = h.audio.stopCount;

    h.notifier.prepareForTtsPlayback();
    expect(h.audio.stopCount, greaterThan(stops));
    expect(h.notifier.state.isRecording, isFalse);

    h.audio.say('echo from speaker', isFinal: true);
    await tester.pump(const Duration(seconds: 5));
    expect(h.notifier.submitted, isEmpty);
    expect(h.audio.startCount, 1, reason: 'no auto restart during playback');
    h.container.dispose();
  });

  testWidgets('leaving Voice AI cancels; returning starts a fresh turn', (
    tester,
  ) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.say('nửa câu');
    h.notifier.cancelListening();
    expect(h.notifier.state.voiceState, VoiceState.idle);
    await tester.pump(const Duration(seconds: 5));
    expect(h.notifier.submitted, isEmpty);

    h.notifier.toggleRecording();
    expect(h.audio.startCount, 2);
    h.audio.ready();
    h.audio.say('câu mới', isFinal: true);
    expect(h.notifier.state.currentTranscript, 'câu mới');
    await tester.pump(const Duration(seconds: 4));
    expect(h.notifier.submitted, ['câu mới']);
    h.container.dispose();
  });

  testWidgets('max session length finalizes the turn', (tester) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    // Keep talking continuously (never 3.5s of silence).
    for (var i = 0; i < 41; i++) {
      h.audio.say('từ $i');
      await tester.pump(const Duration(seconds: 3));
    }
    expect(h.notifier.submitted.length, 1);
    h.container.dispose();
  });

  testWidgets(
    'direct trip voice edit on TripDetailScreen submits directly to editCurrentOrSavedTrip',
    (tester) async {
      final h = _setup();
      final sampleTrip = Trip(
        id: '42',
        title: 'Khám phá Đà Nẵng',
        destination: 'Đà Nẵng',
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 3),
        days: const [],
        status: 'CONFIRMED',
      );

      h.notifier.toggleDirectTripVoiceEdit(trip: sampleTrip, targetDay: 2);
      h.audio.ready();
      h.audio.say('đổi buổi tối đi ăn hải sản Mỹ Khê', isFinal: true);
      await tester.pump(const Duration(seconds: 4));

      expect(
        h.notifier.submitted,
        isEmpty,
        reason: 'should edit trip directly instead of general chat',
      );
      expect(h.notifier.directTripEdits.length, 1);
      expect(h.notifier.directTripEdits.single, (
        instruction: 'đổi buổi tối đi ăn hải sản Mỹ Khê',
        tripId: '42',
        targetDay: 2,
      ));
      expect(h.notifier.isDirectTripEditMode, isFalse);
      h.container.dispose();
    },
  );

  testWidgets('cancelDirectTripVoiceEdit aborts without submitting', (
    tester,
  ) async {
    final h = _setup();
    final sampleTrip = Trip(
      id: '99',
      title: 'Khám phá Hội An',
      destination: 'Hội An',
      startDate: DateTime(2026, 11, 5),
      endDate: DateTime(2026, 11, 7),
      days: const [],
      status: 'CONFIRMED',
    );

    h.notifier.toggleDirectTripVoiceEdit(trip: sampleTrip, targetDay: 1);
    h.audio.ready();
    h.audio.say('thêm phố cổ buổi tối');
    h.notifier.cancelDirectTripVoiceEdit();

    await tester.pump(const Duration(seconds: 5));
    expect(h.notifier.directTripEdits, isEmpty);
    expect(h.notifier.submitted, isEmpty);
    expect(h.notifier.state.voiceState, VoiceState.idle);
    h.container.dispose();
  });

  test(
    'extractNextTtsChunk splits first clause early and protects decimals/abbreviations',
    () {
      // 1. First chunk splits on natural comma pause once >= 22 chars
      const opening =
          'Đà Nẵng mùa này thời tiết rất đẹp, nắng dịu nhẹ và ít mưa.';
      final first = VoiceAssistantNotifier.extractNextTtsChunk(
        opening,
        isFirstChunk: true,
      );
      expect(first, isNotNull);
      expect(first!.chunk, 'Đà Nẵng mùa này thời tiết rất đẹp,');
      expect(first.remainder, 'nắng dịu nhẹ và ít mưa.');

      // 2. Subsequent chunks wait for full sentence boundary instead of short commas
      final secondMidStream = VoiceAssistantNotifier.extractNextTtsChunk(
        'nắng dịu nhẹ, gió mát ',
        isFirstChunk: false,
      );
      expect(secondMidStream, isNull);

      // 3. Does not split mid-decimal ("4.5") or after "TP."
      expect(
        VoiceAssistantNotifier.extractNextTtsChunk(
          'Chi phí khoảng 4.',
          isFirstChunk: true,
        ),
        isNull,
      );
      final cityChunk = VoiceAssistantNotifier.extractNextTtsChunk(
        'Bạn nên ghé thăm TP. Hồ Chí Minh vào tháng ba. Thời tiết rất đẹp!',
        isFirstChunk: true,
      );
      expect(cityChunk, isNotNull);
      expect(
        cityChunk!.chunk,
        'Bạn nên ghé thăm TP. Hồ Chí Minh vào tháng ba.',
      );
    },
  );

  testWidgets(
    'finalPauseFor submits faster on isFinal while keeping full pauseFor on partials',
    (tester) async {
      final audio = FakeVoiceAudioService();
      late _StreamingTestNotifier notifier;
      final provider =
          StateNotifierProvider<_StreamingTestNotifier, VoiceAssistantState>((
            ref,
          ) {
            notifier = _StreamingTestNotifier(ref, audio);
            return notifier;
          });
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      container.read(provider);
      audio.sseController = StreamController<String>();

      notifier.toggleRecording();
      audio.ready();

      // Partial transcript does NOT submit after 700ms (waits for 1200ms pauseFor)
      audio.say('thời tiết Đà Nẵng', isFinal: false);
      await tester.pump(const Duration(milliseconds: 700));
      expect(notifier.state.isRecording, isTrue);

      // Final transcript submits right after 650ms finalPauseFor
      audio.say('thời tiết Đà Nẵng hôm nay', isFinal: true);
      await tester.pump(const Duration(milliseconds: 700));
      expect(notifier.state.isRecording, isFalse);
      expect(notifier.state.voiceState, VoiceState.processing);

      await audio.sseController!.close();
      container.dispose();
    },
  );

  testWidgets(
    'SSE askStream enqueues first clause to TTS before stream finishes and supports bargeIn',
    (tester) async {
      final audio = FakeVoiceAudioService();
      final sse = StreamController<String>();
      audio.sseController = sse;

      late _StreamingTestNotifier notifier;
      final provider =
          StateNotifierProvider<_StreamingTestNotifier, VoiceAssistantState>((
            ref,
          ) {
            notifier = _StreamingTestNotifier(ref, audio);
            return notifier;
          });
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      container.read(provider);

      final sendFuture = notifier.sendMessage(
        'Đà Nẵng có gì vui?',
        isVoiceMode: true,
      );
      await tester.pump();

      sse.add('data: {"type":"init","conversation_id":77}\n\n');
      sse.add(
        'data: {"type":"token","token":"Đà Nẵng mùa này thời tiết rất đẹp, "}\n\n',
      );
      await tester.pump();

      // First clause is already dispatched to TTS BEFORE stream sends 'done' or closes!
      expect(audio.enqueuedSentences, ['Đà Nẵng mùa này thời tiết rất đẹp,']);
      expect(audio.markStreamDoneCount, 0);

      sse.add(
        'data: {"type":"token","token":"rất hợp để tắm biển Mỹ Khê."}\n\n',
      );
      sse.add(
        'data: {"type":"done","conversation_id":77,"content":"Đà Nẵng mùa này thời tiết rất đẹp, rất hợp để tắm biển Mỹ Khê."}\n\n',
      );
      await sse.close();
      await sendFuture;
      await tester.pump();

      expect(audio.enqueuedSentences, [
        'Đà Nẵng mùa này thời tiết rất đẹp,',
        'rất hợp để tắm biển Mỹ Khê.',
      ]);
      expect(audio.markStreamDoneCount, 1);
      audio.finishQueuePlayback();
      notifier.cancelListening();

      // Verify barge-in aborts an active stream immediately
      final sse2 = StreamController<String>();
      audio.sseController = sse2;
      unawaited(notifier.sendMessage('Gợi ý thêm quán ăn', isVoiceMode: true));
      await tester.pump();

      notifier.bargeIn();
      expect(audio.abortStreamCount, greaterThan(0));
      await tester.pump(const Duration(seconds: 3));
      container.dispose();
    },
  );
}
