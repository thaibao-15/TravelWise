import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/audio/voice_audio_service.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';

/// Fake recognizer: records calls and lets tests drive STT callbacks.
class FakeVoiceAudioService implements VoiceAudioService {
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

  @override
  void initStreamingQueue({
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {}

  @override
  void enqueueSentence({
    required String baseUrl,
    required String sentence,
    String speed = '1.25',
    String speakerId = 'HN-Nam-1-BL',
  }) {}

  @override
  void markStreamDone() {}

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
  Future<void> sendMessage(String text, {bool isVoiceMode = false}) async {
    submitted.add(text);
    state = state.copyWith(
      voiceState: VoiceState.processing,
      isRecording: false,
      currentTranscript: text,
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
  final provider =
      StateNotifierProvider<_TestNotifier, VoiceAssistantState>((ref) {
    notifier = _TestNotifier(ref, audio);
    return notifier;
  });
  final container = ProviderContainer();
  container.read(provider);
  return (container: container, notifier: notifier, audio: audio);
}

void main() {
  // testWidgets gives us a FakeAsync zone, so Timers advance with pump().
  testWidgets('short sentence is submitted after the silence threshold',
      (tester) async {
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

  testWidgets('long sentence across many segments is accumulated in order',
      (tester) async {
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

    expect(h.notifier.state.currentTranscript,
        'tôi muốn đi Đà Nẵng ba ngày hai đêm với ngân sách mười triệu');
    expect(h.notifier.submitted, isEmpty);

    await tester.pump(const Duration(seconds: 4));
    expect(h.notifier.submitted,
        ['tôi muốn đi Đà Nẵng ba ngày hai đêm với ngân sách mười triệu']);
    h.container.dispose();
  });

  testWidgets('brief pause then resume keeps listening (old 0.9s bug)',
      (tester) async {
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

  testWidgets('cumulative finals and duplicate finals are not duplicated',
      (tester) async {
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

  testWidgets('silence with no speech stops with a no-speech error',
      (tester) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    await tester.pump(const Duration(seconds: 11));
    expect(h.notifier.submitted, isEmpty);
    expect(h.notifier.state.voiceState, VoiceState.error);
    expect(h.notifier.state.isRecording, isFalse);
    h.container.dispose();
  });

  testWidgets('manual stop submits current text and cancels timers/restart',
      (tester) async {
    final h = _setup();
    h.notifier.toggleRecording();
    h.audio.ready();
    h.audio.say('gợi ý quán cà phê');
    h.notifier.toggleRecording(); // manual stop
    expect(h.notifier.submitted, ['gợi ý quán cà phê']);

    final starts = h.audio.startCount;
    h.audio.done(); // late close from the stopped session
    await tester.pump(const Duration(seconds: 10));
    expect(h.audio.startCount, starts, reason: 'no auto restart after manual stop');
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

  testWidgets('STT error without text shows error; with text submits it',
      (tester) async {
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

  testWidgets('recognizer ending unexpectedly restarts (bounded) and keeps text',
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
  });

  testWidgets('TTS start stops the microphone and ignores late transcripts',
      (tester) async {
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

  testWidgets('leaving Voice AI cancels; returning starts a fresh turn',
      (tester) async {
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
}
