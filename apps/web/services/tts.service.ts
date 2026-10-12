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
   * Lấy URL streaming HTTP trực tiếp từ server để thẻ Audio phát tức thì (TTFB < 500ms)
   */
  getStreamUrl(text: string): string {
    const cleaned = this.cleanText(text);
    if (!cleaned) return "";
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
    return `${apiUrl}/api/v1/tts/stream?text=${encodeURIComponent(cleaned)}`;
  },

  /**
   * Request TTS synthesis and return object audio URL
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
      return { cancel: () => {} };
    }

    window.speechSynthesis.cancel();
    const cleaned = this.cleanText(text);
    if (!cleaned) {
      onEnd?.();
      return { cancel: () => {} };
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
