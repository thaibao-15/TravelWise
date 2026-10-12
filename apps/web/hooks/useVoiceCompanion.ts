"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useSpeechToText } from "@/hooks/useSpeechToText";
import { ttsService } from "@/services/tts.service";

export type VoiceState = "idle" | "listening" | "thinking" | "speaking";

interface UseVoiceCompanionOptions {
  onSendMessage: (text: string, mode?: "chat" | "voice") => Promise<string | null | void>;
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

  // Stop any active audio playback
  const stopAudio = useCallback(() => {
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
    audioRef.current = null;
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
      startRecordingRef.current?.().catch(() => {});
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
      setVoiceState("thinking");
      setStatusMessage("AI đang chuẩn bị câu trả lời...");

      try {
        const spokenAnswer = await onSendMessageRef.current(trimmed, "voice");

        if (autoSpeakRef.current && spokenAnswer && typeof spokenAnswer === "string") {
          const cleanAnswer = ttsService.cleanText(spokenAnswer);
          setVoiceState("speaking");
          setStatusMessage("AI Tour Guide đang đọc câu trả lời...");

          // Luôn sử dụng giọng đọc Blaze AI chuẩn (DaNang-Nu-1-BL cấu hình trong .env)
          try {
            const streamUrl =
              cleanAnswer.length <= 1800
                ? ttsService.getStreamUrl(cleanAnswer)
                : await ttsService.synthesize(cleanAnswer);

            const audio = new Audio(streamUrl);
            audio.preload = "auto";
            audioRef.current = audio;

            audio.onended = () => {
              resumeListeningRef.current();
            };

            audio.onerror = () => {
              console.warn("Blaze TTS stream error, fallback to Web Speech");
              const res = ttsService.speakWebSpeech(
                cleanAnswer,
                () => resumeListeningRef.current(),
                () => resumeListeningRef.current()
              );
              nativeCancelRef.current = res.cancel;
            };

            await audio.play().catch((playErr) => {
              console.warn("Audio play() blocked, fallback to Web Speech:", playErr);
              const res = ttsService.speakWebSpeech(
                cleanAnswer,
                () => resumeListeningRef.current(),
                () => resumeListeningRef.current()
              );
              nativeCancelRef.current = res.cancel;
            });
          } catch (ttsErr) {
            console.warn("TTS synthesize failed, fallback to Web Speech:", ttsErr);
            const res = ttsService.speakWebSpeech(
              cleanAnswer,
              () => resumeListeningRef.current(),
              () => resumeListeningRef.current()
            );
            nativeCancelRef.current = res.cancel;
          }
        } else {
          // Không đọc giọng hoặc không có nội dung: nghe tiếp ngay lập tức
          resumeListeningRef.current();
        }
      } catch (chatErr) {
        console.error("Chat error during speech commit:", chatErr);
        setStatusMessage("Lỗi kết nối khi gửi giọng nói.");
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
      // Khi chat xử lý xong
      if (voiceState === "thinking") {
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
