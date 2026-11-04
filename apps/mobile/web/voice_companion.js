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

        if (self._audioCache[cacheKey]) {
          return Promise.resolve(self._audioCache[cacheKey]);
        }
        if (self._inFlightPrefetch[cacheKey]) {
          return self._inFlightPrefetch[cacheKey];
        }

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
              var oldKey = keys[0];
              try { URL.revokeObjectURL(self._audioCache[oldKey]); } catch(_) {}
              delete self._audioCache[oldKey];
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

      _playAudioUrl: function(audioUrl, item, sessionId) {
        var self = this;
        if (self._isStopped || self._playSessionId !== sessionId) return;

        var fallbackWebSpeech = function() {
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

          audio.onerror = function(e) {
            console.warn('[TravelWise Audio] Sentence chunk error, fallback speech:', e);
            self._stopLipSyncLoop(true);
            fallbackWebSpeech();
          };

          var playPromise = audio.play();
          if (playPromise !== undefined) {
            playPromise.catch(function(error) {
              console.warn('[TravelWise Audio] Stream play error, fallback speech:', error);
              self._stopLipSyncLoop(true);
              fallbackWebSpeech();
            });
          }
        } catch (err) {
          self._stopLipSyncLoop(true);
          if (!self._isStopped && self._playSessionId === sessionId) {
            self._playNextInQueue();
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

        // Never prefetch the first sentence when queue is idle so <audio> streams
        // chunked MP3 directly from Blaze TTS without waiting for full-blob download.
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

      _playNextInQueue: function() {
        var self = this;
        if (self._isStopped) return;

        if (self._queue.length === 0) {
          self._isPlayingQueue = false;
          self._currentAudio = null;
          self._stopLipSyncLoop(true);
          if (self._isStreamDone) {
            if (self._onQueueEnded) {
              var cb = self._onQueueEnded;
              self._onQueueEnded = null;
              cb();
            }
          }
          return;
        }

        self._isPlayingQueue = true;
        var sessionId = self._playSessionId;
        var item = self._queue.shift();
        var cacheKey = item.text + '|' + item.speed + '|' + item.speakerId;

        // Prefetch next queued sentences in background for zero-gap transitions
        self._pumpPrefetch();

        var cachedUrl = self._audioCache[cacheKey];
        if (cachedUrl) {
          self._playAudioUrl(cachedUrl, item, sessionId);
          return;
        }

        // Direct Stream Playback:
        // Play immediately via HTTP chunked stream without waiting for full blob download!
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
          audio.playbackRate = 1.0;
          self._currentAudio = audio;
          var hasAnalyser = self._connectAudioForLipSync(audio);

          audio.onplay = function() {
            console.log('[TravelWise Audio] WAV playback started');
            self._startLipSyncLoop('', hasAnalyser);
            if (onPlayCallback) onPlayCallback();
          };

          audio.onended = function() {
            console.log('[TravelWise Audio] WAV playback finished');
            self._stopLipSyncLoop(true);
            if (onEndedCallback) onEndedCallback();
          };

          audio.onerror = function(e) {
            console.error('[TravelWise Audio] Playback error:', e);
            self._stopLipSyncLoop(true);
            if (onErrorCallback) onErrorCallback('Audio element playback error');
          };

          var playPromise = audio.play();
          if (playPromise !== undefined) {
            playPromise.catch(function(error) {
              console.warn('[TravelWise Audio] Autoplay blocked or error:', error);
              self._stopLipSyncLoop(true);
              if (onErrorCallback) onErrorCallback(error.toString());
            });
          }
        } catch (err) {
          console.error('[TravelWise Audio] Exception playing audio:', err);
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
          } catch(e) {}
          this._currentAudio = null;
        }
        if ('speechSynthesis' in window) {
          try { window.speechSynthesis.cancel(); } catch(e) {}
        }
        if (this._currentUrl) {
          try {
            URL.revokeObjectURL(this._currentUrl);
          } catch(e) {}
          this._currentUrl = null;
        }
      }
    };

    if (!window.__twAudioGestureBound) {
      window.__twAudioGestureBound = true;
      var _twUnlockAudioOnce = function() {
        if (window.TravelWiseAudio) window.TravelWiseAudio.unlockAudio();
        window.removeEventListener('pointerdown', _twUnlockAudioOnce, true);
        window.removeEventListener('touchstart', _twUnlockAudioOnce, true);
        window.removeEventListener('keydown', _twUnlockAudioOnce, true);
      };
      window.addEventListener('pointerdown', _twUnlockAudioOnce, true);
      window.addEventListener('touchstart', _twUnlockAudioOnce, true);
      window.addEventListener('keydown', _twUnlockAudioOnce, true);
    }

    window.TravelWiseRecorder = {
      _ws: null,
      _activeWs: null,
      _audioCtx: null,
      _stream: null,
      _processor: null,
      _source: null,
      _muteNode: null,
      _isRecording: false,
      _canSendAudio: false,
      _chunksSent: 0,
      _permissionGranted: false,
      _closingIntentionally: false,

      _log: function(event, detail) {
        var payload = detail ? Object.assign({ event: event }, detail) : { event: event };
        console.log('[TravelWise STT]', JSON.stringify(payload));
      },

      downsampleTo16k: function(input, inputSampleRate) {
        if (inputSampleRate === 16000) {
          var output = new Int16Array(input.length);
          for (var i = 0; i < input.length; i++) {
            var s = Math.max(-1, Math.min(1, input[i]));
            output[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
          }
          return output;
        }
        var ratio = inputSampleRate / 16000;
        var newLength = Math.round(input.length / ratio);
        var result = new Int16Array(newLength);
        var offsetResult = 0;
        var offsetBuffer = 0;

        while (offsetResult < result.length) {
          var nextOffsetBuffer = Math.round((offsetResult + 1) * ratio);
          var accum = 0;
          var count = 0;
          for (var i = offsetBuffer; i < nextOffsetBuffer && i < input.length; i++) {
            accum += input[i];
            count++;
          }
          var avg = count > 0 ? accum / count : 0;
          var s = Math.max(-1, Math.min(1, avg));
          result[offsetResult] = s < 0 ? s * 0x8000 : s * 0x7fff;
          offsetResult++;
          offsetBuffer = nextOffsetBuffer;
        }
        return result;
      },

      _requestMicrophone: function() {
        var self = this;
        var constraints = {
          audio: {
            channelCount: 1,
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true
          }
        };

        // Only probe permission state for logging; never re-prompt when already granted.
        if (navigator.permissions && navigator.permissions.query && !self._permissionGranted) {
          return navigator.permissions.query({ name: 'microphone' }).then(function(status) {
            self._log('mic_permission_status', { state: status.state });
            return navigator.mediaDevices.getUserMedia(constraints);
          }, function() {
            return navigator.mediaDevices.getUserMedia(constraints);
          });
        }
        return navigator.mediaDevices.getUserMedia(constraints);
      },

      _startAudioPipeline: function(stream, onErrorCallback) {
        var self = this;
        try {
          var AudioCtxClass = window.AudioContext || window.webkitAudioContext;
          // Prefer creating AudioContext while still near the user gesture chain.
          var audioCtx = self._audioCtx || new AudioCtxClass();
          self._audioCtx = audioCtx;

          var resumePromise = audioCtx.state === 'suspended' ? audioCtx.resume() : Promise.resolve();
          return resumePromise.then(function() {
            self._log('audio_context_ready', {
              state: audioCtx.state,
              sampleRate: audioCtx.sampleRate
            });

            var source = audioCtx.createMediaStreamSource(stream);
            self._source = source;

            var processor = audioCtx.createScriptProcessor(4096, 1, 1);
            self._processor = processor;

            var muteNode = audioCtx.createGain();
            muteNode.gain.value = 0;
            self._muteNode = muteNode;

            var chunkQueue = [];
            var totalSamples = 0;
            var hardwareSampleRate = audioCtx.sampleRate;

            processor.onaudioprocess = function(event) {
              if (!self._ws || self._ws.readyState !== WebSocket.OPEN || !self._isRecording || !self._canSendAudio) {
                return;
              }
              var inputData = event.inputBuffer.getChannelData(0);
              var pcm16 = self.downsampleTo16k(inputData, hardwareSampleRate);
              chunkQueue.push(pcm16);
              totalSamples += pcm16.length;

              // ~125ms batches @ 16kHz mono Int16 LE PCM
              if (totalSamples >= 2000) {
                var merged = new Int16Array(totalSamples);
                var offset = 0;
                for (var c = 0; c < chunkQueue.length; c++) {
                  merged.set(chunkQueue[c], offset);
                  offset += chunkQueue[c].length;
                }
                chunkQueue = [];
                totalSamples = 0;
                // Copy buffer so send never detaches our typed array storage.
                self._ws.send(merged.buffer.slice(0));
                self._chunksSent += 1;
                if (self._chunksSent === 1 || self._chunksSent % 20 === 0) {
                  self._log('audio_chunk_sent', {
                    chunksSent: self._chunksSent,
                    bytes: merged.byteLength,
                    sampleRate: 16000
                  });
                }
              }
            };

            source.connect(processor);
            processor.connect(muteNode);
            muteNode.connect(audioCtx.destination);
            self._log('recording_pipeline_started', { hardwareSampleRate: hardwareSampleRate });
          }).catch(function(resumeErr) {
            console.error('[TravelWise STT] AudioContext resume failed:', resumeErr);
            if (onErrorCallback) onErrorCallback('Không thể kích hoạt AudioContext microphone.');
            self.stopRecording();
          });
        } catch (aErr) {
          console.error('[TravelWise STT] Audio pipeline init error:', aErr);
          if (onErrorCallback) onErrorCallback('Không thể khởi tạo bộ xử lý microphone.');
          self.stopRecording();
          return Promise.resolve();
        }
      },

      startRecording: function(wsUrl, onReadyCallback, onTranscriptCallback, onErrorCallback, onDoneCallback) {
        if (this._isRecording) {
          this._log('recording_already_active');
          return;
        }
        this.stopRecording();

        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          if (onErrorCallback) onErrorCallback('Trình duyệt không hỗ trợ microphone hoặc trang chưa dùng HTTPS/localhost.');
          return;
        }

        var self = this;
        self._chunksSent = 0;
        self._canSendAudio = false;
        self._closingIntentionally = false;

        // Create AudioContext early (user-gesture window) so Chrome does not suspend it.
        try {
          var EarlyAudioCtx = window.AudioContext || window.webkitAudioContext;
          self._audioCtx = new EarlyAudioCtx();
          if (self._audioCtx.state === 'suspended') {
            self._audioCtx.resume().catch(function() {});
          }
        } catch (_) {}

        self._requestMicrophone().then(function(stream) {
          self._stream = stream;
          self._permissionGranted = true;
          self._log('mic_permission_granted', {
            tracks: stream.getAudioTracks().map(function(t) {
              return { label: t.label ? '[redacted]' : '', readyState: t.readyState, muted: t.muted };
            })
          });

          try {
            var ws = new WebSocket(wsUrl);
            self._ws = ws;
            self._activeWs = ws;

            ws.onopen = function() {
              if (self._activeWs !== ws) return;
              self._log('stt_ws_opened', { url: wsUrl });
              self._isRecording = true;
              // Build pipeline immediately, but gate PCM until backend/Blaze ready.
              self._startAudioPipeline(stream, onErrorCallback);
            };

            ws.onmessage = function(event) {
              if (self._activeWs !== ws) return;
              try {
                var data = JSON.parse(event.data);
                if (data.type === 'status' && data.status === 'ready') {
                  self._log('stt_ready');
                  self._canSendAudio = true;
                  // Ensure Chrome did not leave AudioContext suspended after async WS open.
                  if (self._audioCtx && self._audioCtx.state === 'suspended') {
                    self._audioCtx.resume().catch(function() {});
                  }
                  if (onReadyCallback) onReadyCallback();
                } else if (data.type === 'status' && data.status === 'stopped') {
                  self._log('stt_stopped_by_server');
                } else if (data.type === 'transcript') {
                  var isFinal = !!(data.is_final || data.isFinal);
                  self._log('transcript_received', {
                    isFinal: isFinal,
                    textLength: data.text ? String(data.text).length : 0
                  });
                  if (data.text && onTranscriptCallback) {
                    onTranscriptCallback(data.text, isFinal);
                  }
                } else if (data.type === 'error') {
                  self._log('stt_error', { message: data.message || 'unknown' });
                  if (onErrorCallback) onErrorCallback(data.message || 'Lỗi STT từ máy chủ');
                  self.stopRecording();
                }
              } catch (pErr) {
                console.error('[TravelWise STT] JSON parse error:', pErr);
              }
            };

            ws.onerror = function() {
              if (self._activeWs !== ws) return;
              self._log('stt_ws_error');
              if (onErrorCallback) onErrorCallback('Lỗi kết nối WebSocket STT');
              self.stopRecording();
            };

            ws.onclose = function(ev) {
              var isActive = self._activeWs === ws;
              self._log('stt_ws_closed', {
                code: ev.code,
                reason: ev.reason || '',
                wasClean: ev.wasClean,
                chunksSent: self._chunksSent,
                intentional: self._closingIntentionally,
                stale: !isActive
              });
              // Never tear down mic/AudioContext owned by a newer recording session.
              if (!isActive) {
                if (onDoneCallback) onDoneCallback();
                return;
              }
              self._activeWs = null;
              self._ws = null;
              self._isRecording = false;
              self._canSendAudio = false;
              self._cleanupHardware();
              if (onDoneCallback) onDoneCallback();
            };
          } catch (wsErr) {
            console.error('[TravelWise STT] WS creation exception:', wsErr);
            if (onErrorCallback) onErrorCallback('Không thể kết nối WebSocket STT');
            self.stopRecording();
          }
        }).catch(function(err) {
          self._log('mic_permission_denied', { name: err && err.name ? err.name : 'unknown' });
          var msg = 'Không thể truy cập microphone.';
          if (err && (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError')) {
            msg = 'Quyền truy cập microphone bị từ chối. Vui lòng bật micro trong cài đặt trình duyệt.';
          } else if (err && (err.name === 'NotFoundError' || err.name === 'DevicesNotFoundError')) {
            msg = 'Không tìm thấy thiết bị microphone.';
          } else if (err && (err.name === 'NotReadableError' || err.name === 'TrackStartError')) {
            msg = 'Microphone đang bị ứng dụng khác chiếm dụng.';
          }
          if (onErrorCallback) onErrorCallback(msg);
          if (onDoneCallback) onDoneCallback();
          self._cleanupHardware();
        });
      },

      stopRecording: function() {
        this._log('recording_stop_requested', { chunksSent: this._chunksSent });
        this._isRecording = false;
        this._canSendAudio = false;
        this._closingIntentionally = true;
        this._cleanupHardware();

        var ws = this._ws;
        // Detach active pointer first so a late onclose cannot wipe a newer session.
        this._ws = null;
        this._activeWs = null;

        if (ws) {
          if (ws.readyState === WebSocket.OPEN) {
            try {
              ws.send(JSON.stringify({ type: 'stop' }));
            } catch (e) {}
            // Let the server acknowledge stop; force-close if hung.
            setTimeout(function() {
              if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
                try { ws.close(); } catch (e2) {}
              }
            }, 1500);
          } else if (ws.readyState === WebSocket.CONNECTING) {
            try { ws.close(); } catch (e3) {}
          }
        }
      },

      _cleanupHardware: function() {
        var hadHardware = !!(this._processor || this._muteNode || this._source || this._stream || this._audioCtx);
        if (this._processor) {
          try { this._processor.disconnect(); } catch(e) {}
          try { this._processor.onaudioprocess = null; } catch(e) {}
          this._processor = null;
        }
        if (this._muteNode) {
          try { this._muteNode.disconnect(); } catch(e) {}
          this._muteNode = null;
        }
        if (this._source) {
          try { this._source.disconnect(); } catch(e) {}
          this._source = null;
        }
        if (this._stream) {
          try {
            this._stream.getTracks().forEach(function(track) { track.stop(); });
          } catch(e) {}
          this._stream = null;
        }
        if (this._audioCtx && this._audioCtx.state !== 'closed') {
          try { this._audioCtx.close(); } catch(e) {}
          this._audioCtx = null;
        }
        if (hadHardware) {
          this._log('mic_tracks_released');
        }
      }
    };

    window.TravelWiseStream = {
      _v: 2,
      _currentController: null,

      abortStream: function() {
        if (this._currentController) {
          try {
            this._currentController.abort();
          } catch (e) {}
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

        console.log('[TravelWiseStream] Starting SSE request to:', url);

        fetch(url, {
          method: 'POST',
          headers: headers,
          body: bodyJson,
          signal: controller.signal
        }).then(function(res) {
          if (!res.ok) {
            return res.text().then(function(errText) {
              var errMsg = 'HTTP ' + res.status + ': ' + (errText || res.statusText);
              console.error('[TravelWiseStream] Server error:', errMsg);
              if (onErrorCallback) onErrorCallback(errMsg);
            });
          }

          if (!res.body) {
            var bodyErr = 'Phản hồi từ máy chủ không có luồng dữ liệu (ReadableStream).';
            console.error('[TravelWiseStream]', bodyErr);
            if (onErrorCallback) onErrorCallback(bodyErr);
            return;
          }

          var reader = res.body.getReader();
          var decoder = new TextDecoder('utf-8');

          function readChunk() {
            reader.read().then(function(result) {
              if (result.done) {
                var flushed = decoder.decode();
                if (flushed && onChunkCallback) {
                  onChunkCallback(flushed);
                }
                if (self._currentController === controller) {
                  self._currentController = null;
                }
                if (onDoneCallback) onDoneCallback();
                return;
              }

              var chunk = decoder.decode(result.value, { stream: true });
              if (chunk && onChunkCallback) {
                onChunkCallback(chunk);
              }
              readChunk();
            }).catch(function(readErr) {
              if (readErr && (readErr.name === 'AbortError' || String(readErr).indexOf('abort') !== -1)) {
                if (onDoneCallback) onDoneCallback();
                return;
              }
              console.error('[TravelWiseStream] Stream read error:', readErr);
              if (self._currentController === controller) {
                self._currentController = null;
              }
              if (onErrorCallback) onErrorCallback(readErr.toString());
            });
          }

          readChunk();
        }).catch(function(fetchErr) {
          if (fetchErr && (fetchErr.name === 'AbortError' || String(fetchErr).indexOf('abort') !== -1)) {
            if (onDoneCallback) onDoneCallback();
            return;
          }
          console.error('[TravelWiseStream] Fetch error:', fetchErr);
          if (self._currentController === controller) {
            self._currentController = null;
          }
          if (onErrorCallback) onErrorCallback(fetchErr.toString());
        });
      }
    };
