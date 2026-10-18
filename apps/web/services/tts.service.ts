/**
 * Text-to-Speech (TTS) Service using TravelWise FastAPI /api/v1/tts endpoint
 * and Web Speech API (zero-latency instant browser speech).
 */

const audioCache = new Map<string, string>();

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

    this.queue.push(clean);
    // Kích hoạt tải trước câu này ngay lập tức dưới nền
    ttsService.prefetchSingle(clean).catch(() => {});

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
          this.playNext();
        }
      };

      await audio.play();
    } catch (err) {
      if (!this.isStopped) {
        console.warn("Play streaming chunk error:", err);
        this.playNext();
      }
    }
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

