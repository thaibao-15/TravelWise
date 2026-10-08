/**
 * Text-to-Speech (TTS) Service using TravelWise FastAPI /api/v1/tts endpoint
 */

const audioCache = new Map<string, string>();

export const ttsService = {
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
    onError?: () => void
  ): { cancel: () => void } {
    if (typeof window === "undefined" || !("speechSynthesis" in window)) {
      onError?.();
      return { cancel: () => {} };
    }

    window.speechSynthesis.cancel();
    const cleaned = this.cleanText(text);
    const utterance = new SpeechSynthesisUtterance(cleaned);

    // Tìm giọng tiếng Việt nếu có trong trình duyệt
    const voices = window.speechSynthesis.getVoices();
    const viVoice = voices.find(
      (v) => v.lang.startsWith("vi") || v.lang.includes("VN")
    );
    if (viVoice) {
      utterance.voice = viVoice;
    }
    utterance.lang = "vi-VN";
    utterance.rate = 1.05;
    utterance.pitch = 1.0;

    utterance.onend = () => onEnd?.();
    utterance.onerror = () => onError?.();

    window.speechSynthesis.speak(utterance);

    return {
      cancel: () => {
        window.speechSynthesis.cancel();
      },
    };
  },
};
