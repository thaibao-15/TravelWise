// ignore_for_file: avoid_web_libraries_in_flutter, uri_does_not_exist, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

class VoiceAudioService {
  VoiceAudioService() {
    _ensureAudioHelper();
    _ensureStreamHelper();
  }

  void _ensureAudioHelper() {
    try {
      if (js_util.getProperty(html.window, 'TravelWiseAudio') != null) return;
      final script = html.ScriptElement()
        ..type = 'text/javascript'
        ..text = r'''
window.TravelWiseAudio = {
  _currentAudio: null,
  _currentUrl: null,
  _audioCache: {},
  _inFlightPrefetch: {},
  _queue: [],
  _isPlayingQueue: false,
  _isStopped: false,
  _isStreamDone: false,
  _hasStartedQueue: false,
  _onQueuePlay: null,
  _onQueueEnded: null,
  _onQueueError: null,
  _audioCtx: null,

  unlockAudio: function() {
    try {
      var AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) {
        if (!this._audioCtx) {
          this._audioCtx = new AudioCtx();
        }
        if (this._audioCtx.state === 'suspended') {
          this._audioCtx.resume();
        }
        var buffer = this._audioCtx.createBuffer(1, 1, 22050);
        var source = this._audioCtx.createBufferSource();
        source.buffer = buffer;
        source.connect(this._audioCtx.destination);
        source.start(0);
      }
    } catch (_) {}
  },

  _buildStreamUrl: function(baseUrl, text, speed, speakerId) {
    var cleanBase = (baseUrl || 'http://127.0.0.1:8000').replace(/\/+$/, '');
    var spd = speed || '1.2';
    var spk = speakerId || 'DaNang-Nu-1-BL';
    return cleanBase + '/api/v1/tts/stream?text=' + encodeURIComponent(text) +
           '&speed=' + encodeURIComponent(spd) +
           '&speaker_id=' + encodeURIComponent(spk);
  },

  prefetchSingle: function(baseUrl, sentence, speed, speakerId) {
    var self = this;
    var clean = (sentence || '').trim();
    if (!clean) return Promise.resolve('');
    var cacheKey = clean + '|' + (speed || '1.2') + '|' + (speakerId || 'DaNang-Nu-1-BL');
    if (self._audioCache[cacheKey]) return Promise.resolve(self._audioCache[cacheKey]);
    if (self._inFlightPrefetch[cacheKey]) return self._inFlightPrefetch[cacheKey];

    var streamUrl = self._buildStreamUrl(baseUrl, clean, speed, speakerId);
    var p = fetch(streamUrl)
      .then(function(res) {
        if (!res.ok) throw new Error('TTS Stream HTTP ' + res.status);
        return res.blob();
      })
      .then(function(blob) {
        var blobUrl = URL.createObjectURL(blob);
        var keys = Object.keys(self._audioCache);
        if (keys.length > 50) {
          try { URL.revokeObjectURL(self._audioCache[keys[0]]); } catch(_) {}
          delete self._audioCache[keys[0]];
        }
        self._audioCache[cacheKey] = blobUrl;
        delete self._inFlightPrefetch[cacheKey];
        return blobUrl;
      })
      .catch(function(err) {
        delete self._inFlightPrefetch[cacheKey];
        throw err;
      });
    self._inFlightPrefetch[cacheKey] = p;
    return p;
  },

  initStreamingQueue: function(onPlayCallback, onEndedCallback, onErrorCallback) {
    this.stop();
    this._isStopped = false;
    this._isStreamDone = false;
    this._isPlayingQueue = false;
    this._hasStartedQueue = false;
    this._queue = [];
    this._onQueuePlay = onPlayCallback || null;
    this._onQueueEnded = onEndedCallback || null;
    this._onQueueError = onErrorCallback || null;
  },

  enqueueSentence: function(baseUrl, sentence, speed, speakerId) {
    if (this._isStopped) return;
    var clean = (sentence || '').trim();
    if (!clean) return;
    this._queue.push({
      baseUrl: baseUrl,
      text: clean,
      speed: speed || '1.2',
      speakerId: speakerId || 'DaNang-Nu-1-BL'
    });
    this.prefetchSingle(baseUrl, clean, speed, speakerId).catch(function() {});
    if (!this._isPlayingQueue) {
      this._playNextInQueue();
    }
  },

  markStreamDone: function() {
    this._isStreamDone = true;
    if (this._queue.length === 0 && !this._isPlayingQueue) {
      if (this._onQueueEnded) {
        var cb = this._onQueueEnded;
        this._onQueueEnded = null;
        cb();
      }
    }
  },

  _playNextInQueue: function() {
    var self = this;
    if (self._isStopped) return;
    if (self._queue.length === 0) {
      self._isPlayingQueue = false;
      self._currentAudio = null;
      if (self._isStreamDone && self._onQueueEnded) {
        var cb = self._onQueueEnded;
        self._onQueueEnded = null;
        cb();
      }
      return;
    }
    self._isPlayingQueue = true;
    var item = self._queue.shift();
    var cacheKey = item.text + '|' + item.speed + '|' + item.speakerId;
    var cachedUrl = self._audioCache[cacheKey];
    var audioUrl = cachedUrl || self._buildStreamUrl(item.baseUrl, item.text, item.speed, item.speakerId);

    if (self._queue.length > 0) {
      var nextItem = self._queue[0];
      self.prefetchSingle(nextItem.baseUrl, nextItem.text, nextItem.speed, nextItem.speakerId).catch(function() {});
    }

    try {
      var audio = new Audio(audioUrl);
      audio.crossOrigin = 'anonymous';
      audio.preload = 'auto';
      self._currentAudio = audio;
      audio.onplay = function() {
        if (!self._hasStartedQueue) {
          self._hasStartedQueue = true;
          if (self._onQueuePlay) self._onQueuePlay();
        }
      };
      audio.onended = function() {
        if (!self._isStopped) self._playNextInQueue();
      };
      var fallbackSpeech = function() {
        if ('speechSynthesis' in window && !self._isStopped) {
          try {
            window.speechSynthesis.cancel();
            var u = new SpeechSynthesisUtterance(item.text);
            u.lang = 'vi-VN';
            u.rate = 1.15;
            window.__twActiveUtterance = u;
            var advanceCalled = false;
            var advance = function() {
              if (advanceCalled) return;
              advanceCalled = true;
              window.__twActiveUtterance = null;
              if (!self._isStopped) self._playNextInQueue();
            };
            var estDurationMs = Math.max(1200, (item.text.length * 85) + 800);
            var speechWatchdog = setTimeout(advance, estDurationMs);

            if (!self._hasStartedQueue) {
              self._hasStartedQueue = true;
              if (self._onQueuePlay) self._onQueuePlay();
            }
            u.onend = function() {
              clearTimeout(speechWatchdog);
              advance();
            };
            u.onerror = function() {
              clearTimeout(speechWatchdog);
              advance();
            };
            window.speechSynthesis.speak(u);
            return;
          } catch (_) {}
        }
        if (!self._isStopped) self._playNextInQueue();
      };
      audio.onerror = function() { fallbackSpeech(); };
      var p = audio.play();
      if (p !== undefined) {
        p.catch(function() { fallbackSpeech(); });
      }
    } catch (_) {
      if (!self._isStopped) self._playNextInQueue();
    }
  },

  playWavBytes: function(byteArray, onPlayCallback, onEndedCallback, onErrorCallback) {
    this.stop();
    try {
      var blob = new Blob([new Uint8Array(byteArray)], { type: 'audio/mpeg' });
      this._currentUrl = URL.createObjectURL(blob);
      var audio = new Audio(this._currentUrl);
      this._currentAudio = audio;
      audio.onplay = function() { if (onPlayCallback) onPlayCallback(); };
      audio.onended = function() { if (onEndedCallback) onEndedCallback(); };
      audio.onerror = function(e) { if (onErrorCallback) onErrorCallback('Lỗi audio'); };
      var p = audio.play();
      if (p !== undefined) {
        p.catch(function(e) { if (onErrorCallback) onErrorCallback(e.toString()); });
      }
    } catch (err) {
      if (onErrorCallback) onErrorCallback(err.toString());
    }
  },

  stop: function() {
    this._isStopped = true;
    this._isPlayingQueue = false;
    this._queue = [];
    if (this._currentAudio) {
      try {
        this._currentAudio.pause();
        this._currentAudio.currentTime = 0;
      } catch (_) {}
      this._currentAudio = null;
    }
    if (this._currentUrl) {
      try { URL.revokeObjectURL(this._currentUrl); } catch (_) {}
      this._currentUrl = null;
    }
  }
};
''';
      html.document.head?.append(script);
      try {
        js_util.callMethod(html.window, 'eval', [script.text ?? '']);
      } catch (_) {}
    } catch (_) {}
  }

  void _ensureStreamHelper() {
    try {
      if (js_util.getProperty(html.window, 'TravelWiseStream') != null) return;
      final script = html.ScriptElement()
        ..type = 'text/javascript'
        ..text = r'''
window.TravelWiseStream = {
  _currentController: null,
  abortStream: function() {
    if (this._currentController) {
      try { this._currentController.abort(); } catch (e) {}
      this._currentController = null;
    }
  },
  askStream: function(url, token, bodyJson, onChunkCallback, onDoneCallback, onErrorCallback) {
    var self = this;
    self.abortStream();
    var controller = new AbortController();
    self._currentController = controller;
    var headers = {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };
    if (token && token !== 'null' && token !== 'undefined' && String(token).trim().length > 0) {
      headers['Authorization'] = 'Bearer ' + String(token).trim();
    }
    fetch(url, {
      method: 'POST',
      headers: headers,
      body: bodyJson,
      signal: controller.signal
    }).then(function(res) {
      if (!res.ok) {
        return res.text().then(function(errText) {
          var errMsg = 'HTTP ' + res.status + ': ' + (errText || res.statusText);
          if (onErrorCallback) onErrorCallback(errMsg);
        });
      }
      if (!res.body) {
        if (onErrorCallback) onErrorCallback('Phản hồi không có luồng body');
        return;
      }
      var reader = res.body.getReader();
      var decoder = new TextDecoder('utf-8');
      function readChunk() {
        reader.read().then(function(result) {
          if (result.done) {
            if (self._currentController === controller) self._currentController = null;
            if (onDoneCallback) onDoneCallback();
            return;
          }
          var chunk = decoder.decode(result.value, { stream: true });
          if (chunk && onChunkCallback) onChunkCallback(chunk);
          readChunk();
        }).catch(function(readErr) {
          if (readErr && (readErr.name === 'AbortError' || String(readErr).indexOf('abort') !== -1)) {
            if (onDoneCallback) onDoneCallback();
            return;
          }
          if (self._currentController === controller) self._currentController = null;
          if (onErrorCallback) onErrorCallback(readErr.toString());
        });
      }
      readChunk();
    }).catch(function(fetchErr) {
      if (fetchErr && (fetchErr.name === 'AbortError' || String(fetchErr).indexOf('abort') !== -1)) {
        if (onDoneCallback) onDoneCallback();
        return;
      }
      if (self._currentController === controller) self._currentController = null;
      if (onErrorCallback) onErrorCallback(fetchErr.toString());
    });
  }
};
''';
      html.document.head?.append(script);
      try {
        js_util.callMethod(html.window, 'eval', [script.text ?? '']);
      } catch (_) {}
    } catch (_) {}
  }

  void initStreamingQueue({
    void Function()? onPlay,
    void Function()? onEnded,
    void Function(String err)? onError,
  }) {
    try {
      _ensureAudioHelper();
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
    String speed = '1.2',
    String speakerId = 'DaNang-Nu-1-BL',
  }) {
    try {
      _ensureAudioHelper();
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
      _ensureAudioHelper();
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
      _ensureAudioHelper();
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) {
        if (onError != null) onError('TravelWiseAudio helper missing');
        return;
      }

      final onPlayJs = js_util.allowInterop(() {
        if (onPlay != null) onPlay();
      });
      final onEndedJs = js_util.allowInterop(() {
        if (onEnded != null) onEnded();
      });
      final onErrorJs = js_util.allowInterop((err) {
        if (onError != null) onError(err?.toString() ?? 'Lỗi phát âm thanh');
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

  void unlockAudio() {
    try {
      _ensureAudioHelper();
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio != null) {
        js_util.callMethod(twAudio, 'unlockAudio', []);
      }
    } catch (_) {}
  }

  void stopTts() {
    try {
      _ensureAudioHelper();
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio != null) {
        js_util.callMethod(twAudio, 'stop', []);
      }
    } catch (_) {}
  }

  void abortStream() {
    try {
      _ensureStreamHelper();
      final twStream = js_util.getProperty(html.window, 'TravelWiseStream');
      if (twStream != null) {
        js_util.callMethod(twStream, 'abortStream', []);
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
          onError('Vui lòng làm mới trang trình duyệt (F5) để cấp quyền microphone.');
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

  Stream<String> askStream({
    required String url,
    String? token,
    required String bodyJson,
  }) {
    final controller = StreamController<String>();
    try {
      _ensureStreamHelper();
      final twStream = js_util.getProperty(html.window, 'TravelWiseStream');
      if (twStream == null) {
        controller.addError('Không thể khởi tạo kết nối stream.');
        controller.close();
        return controller.stream;
      }

      final onChunkJs = js_util.allowInterop((dynamic chunk) {
        if (!controller.isClosed) {
          controller.add(chunk?.toString() ?? '');
        }
      });
      final onDoneJs = js_util.allowInterop(() {
        if (!controller.isClosed) {
          controller.close();
        }
      });
      final onErrorJs = js_util.allowInterop((dynamic err) {
        if (!controller.isClosed) {
          controller.addError(err?.toString() ?? 'Lỗi kết nối stream');
          controller.close();
        }
      });

      js_util.callMethod(twStream, 'askStream', [
        url,
        token,
        bodyJson,
        onChunkJs,
        onDoneJs,
        onErrorJs,
      ]);
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError('Không thể khởi tạo stream: $e');
        controller.close();
      }
    }
    return controller.stream;
  }
}
