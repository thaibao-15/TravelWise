// ignore_for_file: avoid_web_libraries_in_flutter, uri_does_not_exist, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';

import 'lip_sync_frame.dart';

class VoiceAudioService {
  final ValueNotifier<LipSyncFrame> _lipSyncNotifier =
      ValueNotifier<LipSyncFrame>(LipSyncFrame.idle);
  bool _lipSyncBound = false;

  ValueListenable<LipSyncFrame> get lipSyncListenable => _lipSyncNotifier;

  VoiceAudioService() {
    _ensureAudioHelper();
    _ensureStreamHelper();
    _bindLipSyncCallback();
  }

  void _bindLipSyncCallback() {
    if (_lipSyncBound) return;
    try {
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) return;
      final cb = js_util.allowInterop((
        dynamic open,
        dynamic wide,
        dynamic energy,
        dynamic active,
      ) {
        final o = (open is num) ? open.toDouble() : LipSyncFrame.restOpen;
        final w = (wide is num) ? wide.toDouble() : 0.0;
        final e = (energy is num) ? energy.toDouble() : 0.0;
        final isAct = active == true || active == 1;
        _lipSyncNotifier.value = LipSyncFrame(
          mouthOpen: o.clamp(0.0, 1.0),
          mouthWide: w.clamp(-1.0, 1.0),
          energy: e.clamp(0.0, 1.0),
          active: isAct,
        );
      });
      js_util.callMethod(twAudio, 'setLipSyncCallback', [cb]);
      _lipSyncBound = true;
    } catch (_) {}
  }

  void _ensureAudioHelper() {
    try {
      final existing = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (existing != null && js_util.getProperty(existing, '_v') == 4) return;
      _lipSyncBound = false;
      final script = html.ScriptElement()
        ..type = 'text/javascript'
        ..text = r'''
window.TravelWiseAudio = {
  _v: 4,
  _currentAudio: null,
  _currentUrl: null,
  _audioCache: {},
  _inFlightPrefetch: {},
  _queue: [],
  _isPlayingQueue: false,
  _isStopped: false,
  _isStreamDone: false,
  _hasStartedQueue: false,
  _playSessionId: 0,
  _onQueuePlay: null,
  _onQueueEnded: null,
  _onQueueError: null,
  _audioCtx: null,
  _analyser: null,
  _freqBuf: null,
  _timeBuf: null,
  _lipSyncCb: null,
  _lipSyncRaf: null,
  _activeText: '',
  _speechStartPerf: 0,
  _lastSignalPerf: 0,
  _peakRms: 0.14,

  setLipSyncCallback: function(cb) {
    this._lipSyncCb = cb || null;
  },

  unlockAudio: function() {
    try {
      var AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) {
        if (!this._audioCtx) {
          this._audioCtx = new AudioCtx();
        }
        if (this._audioCtx.state === 'suspended') {
          this._audioCtx.resume().catch(function() {});
        }
        var buffer = this._audioCtx.createBuffer(1, 1, 22050);
        var source = this._audioCtx.createBufferSource();
        source.buffer = buffer;
        source.connect(this._audioCtx.destination);
        source.start(0);
      }
    } catch (_) {}
  },

  _ensureAnalyser: function() {
    if (!this._audioCtx) {
      var AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return null;
      this._audioCtx = new AudioCtx();
    }
    if (!this._analyser) {
      this._analyser = this._audioCtx.createAnalyser();
      this._analyser.fftSize = 256;
      this._analyser.smoothingTimeConstant = 0.42;
      this._freqBuf = new Uint8Array(this._analyser.frequencyBinCount);
      this._timeBuf = new Uint8Array(this._analyser.fftSize);
    }
    return this._analyser;
  },

  _connectAudioForLipSync: function(audioEl) {
    try {
      if (!this._audioCtx || this._audioCtx.state !== 'running') return false;
      var analyser = this._ensureAnalyser();
      if (!analyser) return false;
      var src = this._audioCtx.createMediaElementSource(audioEl);
      src.connect(analyser);
      analyser.connect(this._audioCtx.destination);
      return true;
    } catch (_) {
      return false;
    }
  },

  _sampleTextViseme: function(text, elapsedSec) {
    var clean = (text || '').trim();
    if (!clean) {
      var w = 0.5 + 0.5 * Math.sin(elapsedSec * 22.0);
      return { open: 0.14 + w * 0.68, wide: 0.25 * Math.sin(elapsedSec * 9.0), energy: w * 0.8 };
    }
    var tokens = clean.match(/[a-zA-ZÀ-ỹ0-9]+|[,.;:!?–—]/g) || [clean];
    var cursor = 0;
    var beats = [];
    for (var i = 0; i < tokens.length; i++) {
      var tok = tokens[i];
      if (tok.length === 1 && ',.;:!?–—'.indexOf(tok) !== -1) {
        var pd = (tok === ',' || tok === ';' || tok === ':') ? 0.16 : 0.28;
        beats.push({ s: cursor, d: pd, o: 0.18, w: 0.0, pause: true, labial: false });
        cursor += pd;
      } else {
        var dur = 0.155 + Math.min(6, tok.length) * 0.012;
        var o = 0.62, wd = 0.10;
        if (/[aáàảãạăắằẳẵặâấầẩẫậơớờởỡợ]/i.test(tok)) { o = 0.88; wd = 0.25; }
        else if (/[oôuư]/i.test(tok)) { o = 0.74; wd = -0.70; }
        else if (/[iíìỉĩịyýỳỷỹỵeéèẻẽẹêếềểễệ]/i.test(tok)) { o = 0.56; wd = 0.74; }
        var lab = /(^[mbp]|[mp]$)/i.test(tok);
        beats.push({ s: cursor, d: dur, o: o, w: wd, pause: false, labial: lab });
        cursor += dur;
      }
    }
    var t = cursor > 0 ? (elapsedSec % cursor) : 0;
    var active = beats[beats.length - 1];
    for (var j = 0; j < beats.length; j++) {
      if (t >= beats[j].s && t < beats[j].s + beats[j].d) { active = beats[j]; break; }
    }
    if (!active || active.pause) return { open: 0.20, wide: 0.0, energy: 0.05 };
    var ph = Math.max(0, Math.min(1, (t - active.s) / active.d));
    var curve = Math.sin(ph * Math.PI);
    var floor = active.labial ? 0.02 : 0.14;
    return { open: floor + (active.o - floor) * curve, wide: active.w * curve, energy: curve * 0.85 };
  },

  _startLipSyncLoop: function(text, hasAnalyser) {
    var self = this;
    self._stopLipSyncLoop(false);
    self._activeText = text || '';
    self._speechStartPerf = performance.now();
    self._lastSignalPerf = hasAnalyser ? performance.now() : 0;

    var tick = function() {
      if (self._isStopped) {
        self._stopLipSyncLoop(true);
        return;
      }
      var now = performance.now();
      var elapsedSec = (now - self._speechStartPerf) / 1000.0;
      var open = 0.28, wide = 0.0, energy = 0.0;
      var usedPcm = false;

      if (hasAnalyser && self._analyser && self._currentAudio && !self._currentAudio.paused && !self._currentAudio.ended) {
        self._analyser.getByteTimeDomainData(self._timeBuf);
        self._analyser.getByteFrequencyData(self._freqBuf);
        var sumSq = 0;
        for (var i = 0; i < self._timeBuf.length; i++) {
          var v = (self._timeBuf[i] - 128) / 128.0;
          sumSq += v * v;
        }
        var rms = Math.sqrt(sumSq / self._timeBuf.length);
        var f1 = 0, f2 = 0;
        for (var b = 2; b <= 5; b++) f1 += self._freqBuf[b];
        for (var k = 8; k <= 18; k++) f2 += self._freqBuf[k];
        f1 /= 4.0;
        f2 /= 11.0;

        if (rms > 0.007) {
          self._lastSignalPerf = now;
          self._peakRms = Math.max(0.065, self._peakRms * 0.996, rms);
          var norm = Math.min(1.0, (rms - 0.007) / (self._peakRms * 0.80));
          energy = norm;
          if (rms < 0.020) {
            open = 0.04 + (rms / 0.020) * 0.18;
          } else {
            open = 0.26 + Math.pow(norm, 0.70) * 0.74;
          }
          wide = Math.max(-0.9, Math.min(0.9, ((f2 - f1 * 0.76) / (f1 + f2 + 14.0)) * 2.5));
          usedPcm = true;
        } else if (now - self._lastSignalPerf < 240) {
          var gapMs = now - self._lastSignalPerf;
          open = gapMs < 135 ? 0.05 : 0.22;
          wide = 0.0;
          energy = 0.0;
          usedPcm = true;
        }
      }

      if (!usedPcm) {
        var fb = self._sampleTextViseme(self._activeText, elapsedSec);
        open = fb.open;
        wide = fb.wide;
        energy = fb.energy;
      }

      if (self._lipSyncCb) {
        try { self._lipSyncCb(open, wide, energy, true); } catch (_) {}
      }
      self._lipSyncRaf = requestAnimationFrame(tick);
    };
    self._lipSyncRaf = requestAnimationFrame(tick);
  },

  _stopLipSyncLoop: function(emitIdle) {
    if (this._lipSyncRaf) {
      cancelAnimationFrame(this._lipSyncRaf);
      this._lipSyncRaf = null;
    }
    if (emitIdle && this._lipSyncCb) {
      try { this._lipSyncCb(0.28, 0.0, 0.0, false); } catch (_) {}
    }
  },

  _buildStreamUrl: function(baseUrl, text, speed, speakerId) {
    var cleanBase = (baseUrl || 'http://127.0.0.1:8000').replace(/\/+$/, '');
    var spd = speed || '1.5';
    var spk = speakerId || 'DaNang-Nu-1-BL';
    return cleanBase + '/api/v1/tts/stream?text=' + encodeURIComponent(text) +
           '&speed=' + encodeURIComponent(spd) +
           '&speaker_id=' + encodeURIComponent(spk);
  },

  prefetchSingle: function(baseUrl, sentence, speed, speakerId) {
    var self = this;
    var clean = (sentence || '').trim();
    if (!clean) return Promise.resolve('');
    var spd = speed || '1.5';
    var spk = speakerId || 'DaNang-Nu-1-BL';
    var cacheKey = clean + '|' + spd + '|' + spk;
    if (self._audioCache[cacheKey]) return Promise.resolve(self._audioCache[cacheKey]);
    if (self._inFlightPrefetch[cacheKey]) return self._inFlightPrefetch[cacheKey];

    var streamUrl = self._buildStreamUrl(baseUrl, clean, spd, spk);
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

  _pumpPrefetch: function() {
    var self = this;
    if (self._isStopped || self._queue.length === 0) return;
    var activeCount = Object.keys(self._inFlightPrefetch).length;
    for (var i = 0; i < self._queue.length && activeCount < 2; i++) {
      var qItem = self._queue[i];
      var key = qItem.text + '|' + qItem.speed + '|' + qItem.speakerId;
      if (!self._audioCache[key] && !self._inFlightPrefetch[key]) {
        activeCount++;
        self.prefetchSingle(qItem.baseUrl, qItem.text, qItem.speed, qItem.speakerId)
          .then(function() { self._pumpPrefetch(); })
          .catch(function() { self._pumpPrefetch(); });
      }
    }
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
      speed: speed || '1.5',
      speakerId: speakerId || 'DaNang-Nu-1-BL'
    });
    if (!this._isPlayingQueue) {
      this._playNextInQueue();
    } else {
      this._pumpPrefetch();
    }
  },

  markStreamDone: function() {
    this._isStreamDone = true;
    if (this._queue.length === 0 && !this._isPlayingQueue) {
      this._stopLipSyncLoop(true);
      if (this._onQueueEnded) {
        var cb = this._onQueueEnded;
        this._onQueueEnded = null;
        cb();
      }
    }
  },

  _playAudioUrl: function(audioUrl, item, sessionId) {
    var self = this;
    if (self._isStopped || self._playSessionId !== sessionId) return;

    var fallbackSpeech = function() {
      if (self._isStopped || self._playSessionId !== sessionId) return;
      if ('speechSynthesis' in window) {
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
            self._stopLipSyncLoop(true);
            if (!self._isStopped && self._playSessionId === sessionId) {
              self._playNextInQueue();
            }
          };
          var estDurationMs = Math.max(1200, (item.text.length * 85) + 800);
          var speechWatchdog = setTimeout(advance, estDurationMs);

          if (!self._hasStartedQueue) {
            self._hasStartedQueue = true;
            if (self._onQueuePlay) self._onQueuePlay();
          }
          self._startLipSyncLoop(item.text, false);
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
      if (!self._isStopped && self._playSessionId === sessionId) {
        self._playNextInQueue();
      }
    };

    try {
      var audio = new Audio(audioUrl);
      audio.crossOrigin = 'anonymous';
      audio.preload = 'auto';
      audio.playbackRate = 1.0;
      self._currentAudio = audio;
      var hasAnalyser = self._connectAudioForLipSync(audio);
      audio.onplay = function() {
        if (self._isStopped || self._playSessionId !== sessionId) return;
        self._startLipSyncLoop(item.text, hasAnalyser);
        if (!self._hasStartedQueue) {
          self._hasStartedQueue = true;
          if (self._onQueuePlay) self._onQueuePlay();
        }
      };
      audio.onended = function() {
        self._stopLipSyncLoop(self._queue.length === 0);
        if (!self._isStopped && self._playSessionId === sessionId) {
          self._playNextInQueue();
        }
      };
      audio.onerror = function() {
        self._stopLipSyncLoop(true);
        fallbackSpeech();
      };
      var p = audio.play();
      if (p !== undefined) {
        p.catch(function() {
          self._stopLipSyncLoop(true);
          fallbackSpeech();
        });
      }
    } catch (_) {
      self._stopLipSyncLoop(true);
      if (!self._isStopped && self._playSessionId === sessionId) {
        self._playNextInQueue();
      }
    }
  },

  _playNextInQueue: function() {
    var self = this;
    if (self._isStopped) return;
    if (self._queue.length === 0) {
      self._isPlayingQueue = false;
      self._currentAudio = null;
      self._stopLipSyncLoop(true);
      if (self._isStreamDone && self._onQueueEnded) {
        var cb = self._onQueueEnded;
        self._onQueueEnded = null;
        cb();
      }
      return;
    }
    self._isPlayingQueue = true;
    var sessionId = self._playSessionId;
    var item = self._queue.shift();
    var cacheKey = item.text + '|' + item.speed + '|' + item.speakerId;

    self._pumpPrefetch();

    var cachedUrl = self._audioCache[cacheKey];
    if (cachedUrl) {
      self._playAudioUrl(cachedUrl, item, sessionId);
      return;
    }

    // Direct Stream Playback:
    // Play immediately via HTTP chunked stream without waiting for full blob download!
    // Native HTML5 Audio element starts outputting sound on the first chunk (< 200ms).
    var streamUrl = self._buildStreamUrl(item.baseUrl, item.text, item.speed, item.speakerId);
    self._playAudioUrl(streamUrl, item, sessionId);
  },

  playWavBytes: function(byteArray, onPlayCallback, onEndedCallback, onErrorCallback) {
    var self = this;
    self.stop();
    self._isStopped = false;
    try {
      var blob = new Blob([new Uint8Array(byteArray)], { type: 'audio/mpeg' });
      self._currentUrl = URL.createObjectURL(blob);
      var audio = new Audio(self._currentUrl);
      self._currentAudio = audio;
      var hasAnalyser = self._connectAudioForLipSync(audio);
      audio.onplay = function() {
        self._startLipSyncLoop('', hasAnalyser);
        if (onPlayCallback) onPlayCallback();
      };
      audio.onended = function() {
        self._stopLipSyncLoop(true);
        if (onEndedCallback) onEndedCallback();
      };
      audio.onerror = function() {
        self._stopLipSyncLoop(true);
        if (onErrorCallback) onErrorCallback('Lỗi audio');
      };
      var p = audio.play();
      if (p !== undefined) {
        p.catch(function(e) {
          self._stopLipSyncLoop(true);
          if (onErrorCallback) onErrorCallback(e.toString());
        });
      }
    } catch (err) {
      self._stopLipSyncLoop(true);
      if (onErrorCallback) onErrorCallback(err.toString());
    }
  },

  stop: function() {
    this._isStopped = true;
    this._isPlayingQueue = false;
    this._playSessionId += 1;
    this._queue = [];
    this._stopLipSyncLoop(true);
    if (this._currentAudio) {
      try {
        this._currentAudio.pause();
        this._currentAudio.currentTime = 0;
      } catch (_) {}
      this._currentAudio = null;
    }
    if ('speechSynthesis' in window) {
      try { window.speechSynthesis.cancel(); } catch (_) {}
    }
    if (this._currentUrl) {
      try { URL.revokeObjectURL(this._currentUrl); } catch (_) {}
      this._currentUrl = null;
    }
  }
};
if (!window.__twAudioGestureBound) {
  window.__twAudioGestureBound = true;
  var _twUnlockOnce = function() {
    if (window.TravelWiseAudio) window.TravelWiseAudio.unlockAudio();
    window.removeEventListener('pointerdown', _twUnlockOnce, true);
    window.removeEventListener('touchstart', _twUnlockOnce, true);
    window.removeEventListener('keydown', _twUnlockOnce, true);
  };
  window.addEventListener('pointerdown', _twUnlockOnce, true);
  window.addEventListener('touchstart', _twUnlockOnce, true);
  window.addEventListener('keydown', _twUnlockOnce, true);
}
''';
      html.document.head?.append(script);
      try {
        js_util.callMethod(html.window, 'eval', [script.text ?? '']);
      } catch (_) {}
      _bindLipSyncCallback();
    } catch (_) {}
  }

  void _ensureStreamHelper() {
    try {
      final existing = js_util.getProperty(html.window, 'TravelWiseStream');
      if (existing != null && js_util.getProperty(existing, '_v') == 2) return;
      final script = html.ScriptElement()
        ..type = 'text/javascript'
        ..text = r'''
window.TravelWiseStream = {
  _v: 2,
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
            var flushed = decoder.decode();
            if (flushed && onChunkCallback) onChunkCallback(flushed);
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
      _bindLipSyncCallback();
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) return;

      final onPlayJs = js_util.allowInterop(() {
        if (onPlay != null) onPlay();
      });
      final onEndedJs = js_util.allowInterop(() {
        _lipSyncNotifier.value = LipSyncFrame.idle;
        if (onEnded != null) onEnded();
      });
      final onErrorJs = js_util.allowInterop((err) {
        _lipSyncNotifier.value = LipSyncFrame.idle;
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
      _ensureAudioHelper();
      _bindLipSyncCallback();
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
      _bindLipSyncCallback();
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio == null) {
        if (onError != null) onError('TravelWiseAudio helper missing');
        return;
      }

      final onPlayJs = js_util.allowInterop(() {
        if (onPlay != null) onPlay();
      });
      final onEndedJs = js_util.allowInterop(() {
        _lipSyncNotifier.value = LipSyncFrame.idle;
        if (onEnded != null) onEnded();
      });
      final onErrorJs = js_util.allowInterop((err) {
        _lipSyncNotifier.value = LipSyncFrame.idle;
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
      _bindLipSyncCallback();
      final twAudio = js_util.getProperty(html.window, 'TravelWiseAudio');
      if (twAudio != null) {
        js_util.callMethod(twAudio, 'unlockAudio', []);
      }
    } catch (_) {}
  }

  void stopTts() {
    _lipSyncNotifier.value = LipSyncFrame.idle;
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
          onError(
            'Vui lòng làm mới trang trình duyệt (F5) để cấp quyền microphone.',
          );
        }
        return;
      }

      final onReadyJs = js_util.allowInterop(() {
        if (onReady != null) onReady();
      });
      final onTranscriptJs = js_util.allowInterop((
        dynamic text,
        dynamic isFinal,
      ) {
        if (onTranscript == null) return;
        final finalFlag =
            isFinal == true ||
            isFinal == 1 ||
            isFinal?.toString().toLowerCase() == 'true';
        onTranscript(text?.toString() ?? '', finalFlag);
      });
      final onErrorJs = js_util.allowInterop((dynamic err) {
        if (onError != null) {
          onError(err?.toString() ?? 'Lỗi thu âm microphone');
        }
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
