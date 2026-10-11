import 'dart:typed_data';

class VoiceAudioService {
  void playWavBytes(
    Uint8List bytes, {
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {
    onError?.call('Phát âm thanh chưa được hỗ trợ trên nền tảng này.');
  }

  void stopTts() {}

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
}
