"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useSpeechToText } from "@/hooks/useSpeechToText";
import { ttsService, StreamingTTSQueue } from "@/services/tts.service";

export type VoiceState = "idle" | "listening" | "thinking" | "speaking";

interface UseVoiceCompanionOptions {
  onSendMessage: (
    text: string,
    mode?: "chat" | "voice",
    onSentence?: (sentence: string) => void
  ) => Promise<string | null | void>;
  isLoadingChat?: boolean;
}

export function useVoiceCompanion({
  onSendMessage,
  isLoadingChat = false,
}: UseVoiceCompanionOptions) {
  const [voiceState, setVoiceState] = useState<VoiceState>("idle");
  const [autoSpeak, setAutoSpeak] = useState(true);
  const [isHandsFree, setIsHandsFree] = useState(true);
  const [statusMessage, setStatusMessage] = useState("Sẵn sàng lắng nghe bạn...");
  const [transcript, setTranscript] = useState("");

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const cancelAudioRef = useRef<(() => void) | null>(null);
  const activeQueueRef = useRef<StreamingTTSQueue | null>(null);
  const nativeCancelRef = useRef<(() => void) | null>(null);
  const silenceTimerRef = useRef<NodeJS.Timeout | null>(null);
  const lastTranscriptRef = useRef("");

  // Refs to prevent stale closure issues in audio/async callbacks
  const isSessionActiveRef = useRef(false);
  const isHandsFreeRef = useRef(true);
  isHandsFreeRef.current = isHandsFree;
  const autoSpeakRef = useRef(true);
  autoSpeakRef.current = autoSpeak;
  const onSendMessageRef = useRef(onSendMessage);
  onSendMessageRef.current = onSendMessage;
  const isTTSPendingRef = useRef(false);

  // Stop any active audio playback
  const stopAudio = useCallback(() => {
    isTTSPendingRef.current = false;
    if (activeQueueRef.current) {
      activeQueueRef.current.stop();
      activeQueueRef.current = null;
    }
    if (cancelAudioRef.current) {
      cancelAudioRef.current();
      cancelAudioRef.current = null;
    }
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
      audioRef.current = null;
    }
    if (nativeCancelRef.current) {
      nativeCancelRef.current();
      nativeCancelRef.current = null;
    }
  }, []);

  // Handle incoming STT transcript
  const handleTranscript = useCallback((text: string, _isFinal: boolean) => {
    setVoiceState((currentState) => {
      if (currentState === "thinking" || currentState === "speaking") return currentState;
      setTranscript(text);
      lastTranscriptRef.current = text;
      return "listening";
    });
  }, []);

  const {
    isRecording,
    startRecording,
    stopRecording,
    error: sttError,
  } = useSpeechToText({
    onTranscript: handleTranscript,
  });

  const startRecordingRef = useRef(startRecording);
  startRecordingRef.current = startRecording;
  const stopRecordingRef = useRef(stopRecording);
  stopRecordingRef.current = stopRecording;

  // Start listening (sets state to listening immediately to eliminate intermediate delay)
  const startListening = useCallback(async () => {
    isSessionActiveRef.current = true;
    stopAudio();
    setTranscript("");
    lastTranscriptRef.current = "";
    setVoiceState("listening");
    setStatusMessage("Đang lắng nghe giọng nói của bạn...");

    try {
      await startRecordingRef.current?.();
    } catch (err) {
      console.warn("Failed to start audio recording:", err);
      setStatusMessage("Không thể truy cập microphone. Vui lòng cấp quyền.");
      setVoiceState("idle");
      isSessionActiveRef.current = false;
    }
  }, [stopAudio]);

  const startListeningRef = useRef(startListening);
  startListeningRef.current = startListening;

  // Stop listening explicitly (User paused or stopped conversation)
  const stopListening = useCallback(() => {
    isSessionActiveRef.current = false;
    stopRecordingRef.current?.();
    setVoiceState("idle");
    setStatusMessage("Đã tạm dừng. Nhấn micro để tiếp tục trò chuyện.");
  }, []);

  // Helper to resume listening seamlessly when speech playback ends (Zero intermediate step)
  const resumeListeningAfterSpeech = useCallback(() => {
    isTTSPendingRef.current = false;
    audioRef.current = null;
    cancelAudioRef.current = null;
    if (nativeCancelRef.current) {
      nativeCancelRef.current();
      nativeCancelRef.current = null;
    }

    if (isSessionActiveRef.current && isHandsFreeRef.current) {
      // Chuyển thẳng sang nghe người dùng nói tiếp, không qua bước trung gian Bấm để nói!
      setTranscript("");
      lastTranscriptRef.current = "";
      setVoiceState("listening");
      setStatusMessage("Đang lắng nghe câu hỏi tiếp theo của bạn...");
      startRecordingRef.current?.().catch(() => { });
    } else {
      setVoiceState("idle");
      setStatusMessage("Sẵn sàng lắng nghe tiếp...");
    }
  }, []);

  const resumeListeningRef = useRef(resumeListeningAfterSpeech);
  resumeListeningRef.current = resumeListeningAfterSpeech;

  // Commit speech to AI chat
  const commitSpeech = useCallback(
    async (spokenText: string) => {
      const trimmed = spokenText.trim();
      if (!trimmed) return;

      stopRecordingRef.current?.();
      isTTSPendingRef.current = true;
      setVoiceState("thinking");
      setStatusMessage("AI đang chuẩn bị câu trả lời...");

      // Tạo hàng đợi âm thanh phát câu song song (Streaming Audio Queue)
      const queue = new StreamingTTSQueue(
        () => {
          // Khi toàn bộ câu đã đọc xong
          isTTSPendingRef.current = false;
          activeQueueRef.current = null;
          resumeListeningRef.current();
        },
        (err) => {
          console.warn("Streaming TTS queue error:", err);
        },
        () => {
          // Kích hoạt ngay khi CÂU ĐẦU TIÊN bắt đầu phát ra loa (Zero Latency!)
          setVoiceState("speaking");
          setStatusMessage("AI Tour Guide đang đọc câu trả lời...");
          stopRecordingRef.current?.();
        }
      );
      activeQueueRef.current = queue;

      try {
        const spokenAnswer = await onSendMessageRef.current(
          trimmed,
          "voice",
          (sentence) => {
            if (autoSpeakRef.current) {
              queue.enqueue(sentence);
            }
          }
        );

        if (autoSpeakRef.current && spokenAnswer && typeof spokenAnswer === "string") {
          queue.markStreamDone();
        } else {
          queue.stop();
          activeQueueRef.current = null;
          isTTSPendingRef.current = false;
          resumeListeningRef.current();
        }
      } catch (chatErr) {
        console.error("Chat error during speech commit:", chatErr);
        setStatusMessage("Lỗi kết nối khi gửi giọng nói.");
        if (activeQueueRef.current) {
          activeQueueRef.current.stop();
          activeQueueRef.current = null;
        }
        isTTSPendingRef.current = false;
        resumeListeningRef.current();
      }
    },
    []
  );

  // Auto silence commit in hands-free mode (750ms để bắt câu nói siêu nhạy)
  useEffect(() => {
    if (!isRecording || voiceState !== "listening") return;

    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
    }

    if (transcript && transcript.trim().length > 1) {
      // Khi người dùng ngừng nói 750ms, tự động gửi câu hỏi ngay lập tức
      silenceTimerRef.current = setTimeout(() => {
        commitSpeech(transcript);
      }, 750);
    }

    return () => {
      if (silenceTimerRef.current) {
        clearTimeout(silenceTimerRef.current);
      }
    };
  }, [transcript, isRecording, voiceState, commitSpeech]);

  // Update status on chat loading and restore listening when done
  useEffect(() => {
    if (isLoadingChat) {
      if (voiceState !== "thinking" && voiceState !== "speaking") {
        setVoiceState("thinking");
        setStatusMessage("Đang chuẩn bị câu trả lời...");
      }
    } else {
      // Khi chat xử lý xong: chỉ nghe lại nếu KHÔNG có tác vụ TTS đang chuẩn bị phát
      if (voiceState === "thinking" && !isTTSPendingRef.current) {
        if (isSessionActiveRef.current) {
          resumeListeningRef.current();
        } else {
          setVoiceState("idle");
          setStatusMessage("Sẵn sàng lắng nghe bạn...");
        }
      }
    }
  }, [isLoadingChat, voiceState]);

  // STT error handling
  useEffect(() => {
    if (sttError) {
      setStatusMessage(`Microphone: ${sttError}`);
      if (voiceState === "listening") {
        setVoiceState("idle");
        isSessionActiveRef.current = false;
      }
    }
  }, [sttError, voiceState]);

  return {
    voiceState,
    isRecording,
    transcript,
    autoSpeak,
    isHandsFree,
    statusMessage,
    startListening,
    stopListening,
    stopAudio: () => {
      stopAudio();
      setVoiceState((prev) => (prev === "speaking" ? "idle" : prev));
    },
    toggleAutoSpeak: () => setAutoSpeak((prev) => !prev),
    toggleHandsFree: () => setIsHandsFree((prev) => !prev),
  };
}
