/**
 * Text-to-Speech service using the TravelWise FastAPI proxy.
 * The proxy connects to Blaze TTS Realtime V1; the browser never receives the API key.
 */

const audioCache = new Map<string, string>();

export interface IncrementalTtsChunkingConfig {
  minChars: number;
  preferredChars: number;
  maxChars: number;
  maxWaitMs: number;
  maxQueuedChunks: number;
}

/**
 * Starting values for incremental TTS. They are intentionally configurable so
 * latency/quality benchmarks can tune them without changing the chunker.
 */
export const incrementalTtsConfig: IncrementalTtsChunkingConfig = {
  minChars: 56,
  preferredChars: 120,
  maxChars: 220,
  maxWaitMs: 400,
  maxQueuedChunks: 12,
};

export class IncrementalTtsChunker {
  private buffer = "";
  private timer: ReturnType<typeof setTimeout> | null = null;
  private stopped = false;

  constructor(
    private readonly onChunk: (chunk: string) => void,
    private readonly config: IncrementalTtsChunkingConfig = incrementalTtsConfig,
  ) {}

  push(token: string): void {
    if (this.stopped || !token) return;

    this.buffer += token;
    this.drain(false);
    this.scheduleFlush();
  }

  flush(): void {
    if (this.stopped) return;
    this.clearTimer();
    this.drain(true);
  }

  cancel(): void {
    this.stopped = true;
    this.buffer = "";
    this.clearTimer();
  }

  private drain(force: boolean, allowShortTail = true): void {
    while (this.buffer) {
      if (!allowShortTail && this.buffer.length < this.config.minChars) return;
      const cut = this.findCut(force);
      if (cut === null) return;

      const chunk = this.buffer.slice(0, cut).trim();
      this.buffer = this.buffer.slice(cut);
      if (chunk) this.onChunk(chunk);
    }
  }

  private findCut(force: boolean): number | null {
    const length = this.buffer.length;
    if (!length) return null;

    const whitespace: number[] = [];
    for (let index = 0; index < this.buffer.length; index += 1) {
      if (/\s/u.test(this.buffer[index])) whitespace.push(index + 1);
    }
    const usableWhitespace = whitespace.filter((index) => index > 0 && index < length);
    const punctuation: number[] = [];
    for (let index = 0; index < this.buffer.length; index += 1) {
      if (
        /[.!?\n]/u.test(this.buffer[index]) &&
        index + 1 >= this.config.minChars
      ) {
        punctuation.push(index + 1);
      }
    }

    // Punctuation improves prosody when available, but is never required.
    const punctuationCut = punctuation.find((index) => index <= this.config.maxChars);
    if (punctuationCut !== undefined) return punctuationCut;

    if (length < this.config.minChars && !force) return null;
    if (force && length < this.config.minChars) return length;

    const preferredCut = usableWhitespace.find(
      (index) => index >= this.config.preferredChars && index <= this.config.maxChars,
    );
    if (preferredCut !== undefined) return preferredCut;

    if (length >= this.config.maxChars || force) {
      const lastCut = usableWhitespace
        .filter((index) => index >= this.config.minChars && index <= this.config.maxChars)
        .pop();
      return lastCut ?? (force && length >= this.config.minChars ? length : null);
    }

    return null;
  }

  private scheduleFlush(): void {
    if (!this.buffer || this.timer !== null || this.stopped) return;

    this.timer = setTimeout(() => {
      this.timer = null;
      // Avoid sending tiny fragments just because token delivery paused briefly.
      // The stream's final flush still speaks any short tail.
      this.drain(this.buffer.length >= this.config.minChars, false);
    }, this.config.maxWaitMs);
  }

  private clearTimer(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }
}

// Pre-cached Vietnamese voice
let cachedViVoice: SpeechSynthesisVoice | null = null;

if (typeof window !== "undefined" && "speechSynthesis" in window) {
  const findViVoice = () => {
    try {
      const voices = window.speechSynthesis.getVoices();
      cachedViVoice =
        voices.find((v) => v.lang === "vi-VN" || v.lang.startsWith("vi") || v.lang.includes("VN")) ||
        voices.find((v) => /vietnam|tiếng việt/i.test(v.name)) ||
        null;
    } catch {
      // Ignore
    }
  };

  findViVoice();
  if (typeof window.speechSynthesis.onvoiceschanged !== "undefined") {
    window.speechSynthesis.onvoiceschanged = findViVoice;
  }
}

const inFlightPrefetch = new Map<string, Promise<string>>();

export const ttsService = {
  /**
   * Khởi động sớm giọng đọc trình duyệt ngay khi vào trang
   */
  warmup(): void {
    if (typeof window !== "undefined" && "speechSynthesis" in window) {
      try {
        window.speechSynthesis.getVoices();
      } catch { }
    }
  },

  /**
   * Làm sạch văn bản trước khi đưa vào bộ đọc TTS (bỏ markdown, links, emojis)
   */
  cleanText(text: string): string {
    return text
      .replace(/```[\s\S]*?```/g, "")
      .replace(/`.*?`/g, "")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/[*_~#>-]/g, " ")
      .replace(/https?:\/\/\S+/g, "")
      .replace(/\s+/g, " ")
      .trim();
  },

  /**
   * Lấy URL streaming HTTP trực tiếp từ server để thẻ Audio phát tức thì
   */
  getStreamUrl(text: string): string {
    const cleaned = this.cleanText(text);
    if (!cleaned) return "";
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
    return `${apiUrl}/api/v1/tts/stream?text=${encodeURIComponent(cleaned)}`;
  },

  /**
   * Tách đoạn văn thành danh sách các câu hoàn chỉnh tự nhiên
   * Giúp phát âm thanh câu đầu tiên ngay lập tức (Zero Latency) trong khi các câu sau nạp nền
   */
  splitSentences(text: string): string[] {
    const cleaned = this.cleanText(text);
    if (!cleaned) return [];

    // Tách theo dấu câu . ! ? hoặc xuống dòng
    const raw = cleaned.split(/(?<=[.!?\n])\s+/);
    const sentences: string[] = [];
    let current = "";

    for (const part of raw) {
      const p = part.trim();
      if (!p) continue;
      // Nếu câu quá ngắn (< 45 ký tự), ghép với câu trước để đọc tự nhiên, tránh bị ngắt vụn
      if (current.length > 0 && current.length + p.length < 55) {
        current += " " + p;
      } else {
        if (current) sentences.push(current);
        current = p;
      }
    }
    if (current) sentences.push(current);
    return sentences.length > 0 ? sentences : [cleaned];
  },

  /**
   * Lấy URL âm thanh đã lưu sẵn trong cache nếu có
   */
  getCachedAudioUrl(text: string): string | null {
    const cleaned = this.cleanText(text);
    return cleaned ? audioCache.get(cleaned) || null : null;
  },

  /**
   * Nạp trước (Pre-fetch) 1 câu đơn lẻ vào bộ nhớ đệm Blob
   */
  async prefetchSingle(sentence: string): Promise<string> {
    const cleaned = this.cleanText(sentence);
    if (!cleaned) return "";

    if (audioCache.has(cleaned)) {
      return audioCache.get(cleaned)!;
    }

    if (inFlightPrefetch.has(cleaned)) {
      return inFlightPrefetch.get(cleaned)!;
    }

    const streamUrl = this.getStreamUrl(cleaned);
    const fetchPromise = (async () => {
      try {
        const res = await fetch(streamUrl);
        if (!res.ok) {
          throw new Error(`TTS Stream HTTP ${res.status}`);
        }
        const blob = await res.blob();
        const blobUrl = URL.createObjectURL(blob);
        audioCache.set(cleaned, blobUrl);
        return blobUrl;
      } finally {
        inFlightPrefetch.delete(cleaned);
      }
    })();

    inFlightPrefetch.set(cleaned, fetchPromise);
    return fetchPromise;
  },

  /**
   * Nạp trước âm thanh của đoạn văn: tách câu và nạp song song từng câu
   * Trả về blob URL của câu đầu tiên để phát ngay lập tức
   */
  async prefetch(text: string): Promise<string> {
    const sentences = this.splitSentences(text);
    if (sentences.length === 0) return "";

    // Kích hoạt tải song song tất cả các câu
    const promises = sentences.map((s) => this.prefetchSingle(s));

    // Trả về câu đầu tiên ngay khi câu đầu sẵn sàng (không chờ toàn bộ đoạn)
    return await promises[0];
  },

  /**
   * Phát toàn bộ đoạn văn theo luồng nối tiếp từng câu (Sentence Queue)
   * Câu 1 phát NGAY LẬP TỨC (< 300ms qua chunked stream), các câu sau nạp trước dưới nền
   */
  async playAudio(
    text: string,
    onEnd?: () => void,
    onError?: (err: any) => void
  ): Promise<{ cancel: () => void }> {
    const sentences = this.splitSentences(text);
    if (sentences.length === 0) {
      onEnd?.();
      return { cancel: () => { } };
    }

    let isCancelled = false;
    let currentAudio: HTMLAudioElement | null = null;
    let currentIndex = 0;

    // Nạp trước các câu tiếp theo dưới nền
    sentences.slice(1).forEach((s) => this.prefetchSingle(s).catch(() => { }));

    const playNext = async () => {
      if (isCancelled) return;
      if (currentIndex >= sentences.length) {
        onEnd?.();
        return;
      }

      const currentSentence = sentences[currentIndex];
      currentIndex++;

      try {
        // Dùng cache blob nếu có, ngược lại dùng streamUrl trực tiếp để phát ngay lập tức
        const cachedUrl = this.getCachedAudioUrl(currentSentence);
        const audioUrl = cachedUrl || this.getStreamUrl(currentSentence);
        if (isCancelled) return;

        if (!cachedUrl) {
          this.prefetchSingle(currentSentence).catch(() => { });
        }

        const audio = new Audio(audioUrl);
        audio.preload = "auto";
        currentAudio = audio;

        audio.onended = () => {
          if (!isCancelled) {
            playNext();
          }
        };

        audio.onerror = (e) => {
          if (!isCancelled) {
            console.warn(`TTS error on sentence ${currentIndex}/${sentences.length}:`, e);
            playNext();
          }
        };

        await audio.play();
      } catch (err) {
        if (!isCancelled) {
          console.warn("Play sentence failed, skipping to next:", err);
          if (currentIndex >= sentences.length) {
            onError?.(err);
          } else {
            playNext();
          }
        }
      }
    };

    // Bắt đầu phát câu đầu tiên tức thì
    playNext();

    return {
      cancel: () => {
        isCancelled = true;
        if (currentAudio) {
          currentAudio.pause();
          currentAudio.currentTime = 0;
          currentAudio = null;
        }
      },
    };
  },

  /**
   * Request TTS synthesis and return object audio URL (fallback POST)
   */
  async synthesize(text: string): Promise<string> {
    const cleaned = this.cleanText(text);
    if (!cleaned) throw new Error("Văn bản rỗng");

    if (audioCache.has(cleaned)) {
      return audioCache.get(cleaned)!;
    }

    const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
    const res = await fetch(`${apiUrl}/api/v1/tts`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ text: cleaned }),
    });

    if (!res.ok) {
      const errJson = await res.json().catch(() => ({}));
      throw new Error(errJson.detail || "Không thể tạo âm thanh từ dịch vụ Blaze TTS.");
    }

    const blob = await res.blob();
    const objectUrl = URL.createObjectURL(blob);
    audioCache.set(cleaned, objectUrl);
    return objectUrl;
  },

  /**
   * Phát giọng đọc siêu tốc bằng Web Speech API trình duyệt (0ms latency, không qua server)
   */
  speakWebSpeech(
    text: string,
    onEnd?: () => void,
    onError?: () => void,
    onStart?: () => void
  ): { cancel: () => void } {
    if (typeof window === "undefined" || !("speechSynthesis" in window)) {
      onError?.();
      return { cancel: () => { } };
    }

    window.speechSynthesis.cancel();
    const cleaned = this.cleanText(text);
    if (!cleaned) {
      onEnd?.();
      return { cancel: () => { } };
    }

    const utterance = new SpeechSynthesisUtterance(cleaned);

    // Ưu tiên dùng giọng tiếng Việt đã cache
    if (cachedViVoice) {
      utterance.voice = cachedViVoice;
    } else {
      const voices = window.speechSynthesis.getVoices();
      const viVoice =
        voices.find((v) => v.lang === "vi-VN" || v.lang.startsWith("vi") || v.lang.includes("VN")) ||
        voices.find((v) => /vietnam|tiếng việt/i.test(v.name));
      if (viVoice) {
        cachedViVoice = viVoice;
        utterance.voice = viVoice;
      }
    }

    utterance.lang = "vi-VN";
    utterance.rate = 1.08; // Tốc độ phản hồi tự nhiên, không rề rà
    utterance.pitch = 1.0;

    utterance.onstart = () => onStart?.();
    utterance.onend = () => onEnd?.();
    utterance.onerror = (e) => {
      if (e.error !== "canceled" && e.error !== "interrupted") {
        onError?.();
      }
    };

    window.speechSynthesis.speak(utterance);

    return {
      cancel: () => {
        try {
          window.speechSynthesis.cancel();
        } catch { }
      },
    };
  },
};

/**
 * Hàng đợi âm thanh phát câu song song theo luồng thời gian thực (Streaming TTS Queue)
 * Cho phép phát âm thanh câu đầu tiên NGAY LẬP TỨC trong khi LLM vẫn đang stream các câu sau!
 */
export class StreamingTTSQueue {
  private queue: string[] = [];
  private isPlaying = false;
  private currentAudio: HTMLAudioElement | null = null;
  private isStopped = false;
  private isStreamDone = false;
  private onFinishedCallback: (() => void) | null = null;
  private onErrorCallback: ((err: any) => void) | null = null;
  private onStartedCallback: (() => void) | null = null;
  private hasStarted = false;

  constructor(
    onFinished?: () => void,
    onError?: (err: any) => void,
    onStarted?: () => void
  ) {
    this.onFinishedCallback = onFinished || null;
    this.onErrorCallback = onError || null;
    this.onStartedCallback = onStarted || null;
  }

  enqueue(sentence: string) {
    if (this.isStopped) return;
    const clean = ttsService.cleanText(sentence);
    if (!clean) return;

    if (this.queue.length >= incrementalTtsConfig.maxQueuedChunks) {
      const lastIndex = this.queue.length - 1;
      this.queue[lastIndex] = `${this.queue[lastIndex]} ${clean}`;
    } else {
      this.queue.push(clean);
    }
    this.prefetchQueuedChunks();

    if (!this.isPlaying) {
      this.playNext();
    }
  }

  markStreamDone() {
    this.isStreamDone = true;
    if (!this.isPlaying && this.queue.length === 0) {
      this.onFinishedCallback?.();
    }
  }

  private async playNext() {
    if (this.isStopped) return;

    if (this.queue.length === 0) {
      this.isPlaying = false;
      if (this.isStreamDone) {
        this.onFinishedCallback?.();
      }
      return;
    }

    this.isPlaying = true;
    const sentence = this.queue.shift()!;
    this.prefetchQueuedChunks();

    try {
      // 1. Dùng cache blob nếu có (0ms), ngược lại dùng streamUrl trực tiếp để phát chunk đầu tiên ngay (< 300ms)
      const cachedUrl = ttsService.getCachedAudioUrl(sentence);
      const audioUrl = cachedUrl || ttsService.getStreamUrl(sentence);

      if (this.isStopped) return;

      if (!cachedUrl) {
        ttsService.prefetchSingle(sentence).catch(() => {});
      }

      const audio = new Audio(audioUrl);
      audio.preload = "auto";
      this.currentAudio = audio;

      audio.onplay = () => {
        if (!this.hasStarted) {
          this.hasStarted = true;
          this.onStartedCallback?.();
        }
      };

      audio.onended = () => {
        if (!this.isStopped) {
          this.playNext();
        }
      };

      audio.onerror = (e) => {
        if (!this.isStopped) {
          console.warn("Streaming audio error on chunk:", e);
          this.onErrorCallback?.(new Error("Không thể phát audio TTS."));
          this.playNext();
        }
      };

      await audio.play();
    } catch (err) {
      if (!this.isStopped) {
        console.warn("Play streaming chunk error:", err);
        this.onErrorCallback?.(err);
        this.playNext();
      }
    }
  }

  private prefetchQueuedChunks(): void {
    this.queue.slice(0, 2).forEach((chunk) => {
      ttsService.prefetchSingle(chunk).catch((err) => {
        if (!this.isStopped) this.onErrorCallback?.(err);
      });
    });
  }

  stop() {
    this.isStopped = true;
    this.queue = [];
    if (this.currentAudio) {
      this.currentAudio.pause();
      this.currentAudio.currentTime = 0;
      this.currentAudio = null;
    }
  }
}
