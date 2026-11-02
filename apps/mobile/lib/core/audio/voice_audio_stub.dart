import 'dart:async';
import 'package:flutter/foundation.dart';

import 'lip_sync_frame.dart';

class VoiceAudioService {
  final ValueNotifier<LipSyncFrame> _lipSyncNotifier =
      ValueNotifier<LipSyncFrame>(LipSyncFrame.idle);

  ValueListenable<LipSyncFrame> get lipSyncListenable => _lipSyncNotifier;

  void initStreamingQueue({
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {}

  void enqueueSentence({
    required String baseUrl,
    required String sentence,
    String speed = '1.5',
    String speakerId = 'DaNang-Nu-1-BL',
  }) {}

  void markStreamDone() {}

  void playWavBytes(
    Uint8List bytes, {
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {
    onError?.call('Phát âm thanh chưa được hỗ trợ trên nền tảng này.');
  }

  void unlockAudio() {}

  void stopTts() {
    _lipSyncNotifier.value = LipSyncFrame.idle;
  }

  void startRecording({
    required String wsUrl,
    void Function()? onReady,
    void Function(String text, bool isFinal)? onTranscript,
    void Function(String err)? onError,
    void Function()? onDone,
  }) {
    onError?.call('Thu âm microphone chưa được hỗ trợ trên nền tảng này.');
  }

  void stopRecording() {}

  void abortStream() {}

  Stream<String> askStream({
    required String url,
    String? token,
    required String bodyJson,
  }) {
    return const Stream<String>.empty();
  }
}
