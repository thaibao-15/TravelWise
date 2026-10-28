// ignore_for_file: avoid_web_libraries_in_flutter, uri_does_not_exist, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

class VoiceAudioService {
  void initStreamingQueue({
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {
    try {
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) return;

      final onPlayJs = js_util.allowInterop(() {
        if (onPlay != null) onPlay();
      });
      final onEndedJs = js_util.allowInterop(() {
        if (onEnded != null) onEnded();
      });
      final onErrorJs = js_util.allowInterop((err) {
        if (onError != null) onError(err?.toString() ?? 'Lỗi phát stream TTS');
      });

      js_util.callMethod(twAudio, 'initStreamingQueue', [
        onPlayJs,
        onEndedJs,
        onErrorJs,
      ]);
    } catch (_) {}
  }

  void enqueueSentence({
    required String baseUrl,
    required String sentence,
    String speed = '1.5',
    String speakerId = 'DaNang-Nu-1-BL',
  }) {
    try {
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) return;
      js_util.callMethod(twAudio, 'enqueueSentence', [
        baseUrl,
        sentence,
        speed,
        speakerId,
      ]);
    } catch (_) {}
  }

  void markStreamDone() {
    try {
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio != null) {
        js_util.callMethod(twAudio, 'markStreamDone', []);
      }
    } catch (_) {}
  }

  void playWavBytes(
    Uint8List bytes, {
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {
    try {
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) {
        if (onError != null) onError('TravelWiseAudio JavaScript helper missing in web/index.html');
        return;
      }

      final onPlayJs = js_util.allowInterop(() {
        if (onPlay != null) onPlay();
      });
      final onEndedJs = js_util.allowInterop(() {
        if (onEnded != null) onEnded();
      });
      final onErrorJs = js_util.allowInterop((err) {
        if (onError != null) onError(err?.toString() ?? 'Lỗi phát âm thanh WAV');
      });

      js_util.callMethod(twAudio, 'playWavBytes', [
        bytes,
        onPlayJs,
        onEndedJs,
        onErrorJs,
      ]);
    } catch (e) {
      if (onError != null) onError('Không thể phát âm thanh: $e');
    }
  }

  void stopTts() {
    try {
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio != null) {
        js_util.callMethod(twAudio, 'stop', []);
      }
    } catch (_) {}
  }

  void startRecording({
    required String wsUrl,
    void Function()? onReady,
    void Function(String text, bool isFinal)? onTranscript,
    void Function(String err)? onError,
    void Function()? onDone,
  }) {
    try {
      final twRecorder = js_util.getProperty(html.window, 'TravelWiseRecorder');
      if (twRecorder == null) {
        if (onError != null) {
          onError('TravelWiseRecorder JavaScript helper missing in web/index.html');
        }
        return;
      }

      final onReadyJs = js_util.allowInterop(() {
        if (onReady != null) onReady();
      });
      final onTranscriptJs = js_util.allowInterop((dynamic text, dynamic isFinal) {
        if (onTranscript == null) return;
        final finalFlag = isFinal == true ||
            isFinal == 1 ||
            isFinal?.toString().toLowerCase() == 'true';
        onTranscript(text?.toString() ?? '', finalFlag);
      });
      final onErrorJs = js_util.allowInterop((dynamic err) {
        if (onError != null) onError(err?.toString() ?? 'Lỗi thu âm microphone');
      });
      final onDoneJs = js_util.allowInterop(() {
        if (onDone != null) onDone();
      });

      js_util.callMethod(twRecorder, 'startRecording', [
        wsUrl,
        onReadyJs,
        onTranscriptJs,
        onErrorJs,
        onDoneJs,
      ]);
    } catch (e) {
      if (onError != null) onError('Không thể khởi chạy thu âm: $e');
    }
  }

  void stopRecording() {
    try {
      final twRecorder = js_util.getProperty(html.window, 'TravelWiseRecorder');
      if (twRecorder != null) {
        js_util.callMethod(twRecorder, 'stopRecording', []);
      }
    } catch (_) {}
  }
}
