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
    setVoiceState((prev) => (prev === "speaking" ? "idle" : prev));
  }, []);

  // Handle incoming STT transcript
  const handleTranscript = useCallback((text: string, _isFinal: boolean) => {
    if (voiceState === "thinking" || voiceState === "speaking") return;
    setTranscript(text);
    lastTranscriptRef.current = text;
  }, [voiceState]);

  const {
    isRecording,
    startRecording,
    stopRecording,
    error: sttError,
  } = useSpeechToText({
    onTranscript: handleTranscript,
  });

  // Start listening
  const startListening = useCallback(async () => {
    stopAudio();
    setTranscript("");
    lastTranscriptRef.current = "";
    await startRecording();
    setVoiceState("listening");
    setStatusMessage("Đang lắng nghe giọng nói của bạn...");
  }, [stopAudio, startRecording]);

  // Stop listening
  const stopListening = useCallback(() => {
    stopRecording();
    if (voiceState === "listening") {
      setVoiceState("idle");
      setStatusMessage("Đã tạm dừng lắng nghe.");
    }
  }, [stopRecording, voiceState]);

  // Commit speech to AI chat
  const commitSpeech = useCallback(
    async (spokenText: string) => {
      const trimmed = spokenText.trim();
      if (!trimmed) return;

      stopRecording();
      setVoiceState("thinking");
      setStatusMessage("AI đang suy nghĩ và chuẩn bị phản hồi...");

      try {
        const spokenAnswer = await onSendMessage(trimmed, "voice");

        if (autoSpeak && spokenAnswer) {
          setVoiceState("speaking");
          setStatusMessage("AI Tour Guide đang đọc câu trả lời...");

          try {
            const audioUrl = await ttsService.synthesize(spokenAnswer);
            const audio = new Audio(audioUrl);
            audioRef.current = audio;

            audio.onended = () => {
              audioRef.current = null;
              setVoiceState("idle");
              setStatusMessage("Sẵn sàng lắng nghe tiếp...");
              if (isHandsFree) {
                setTimeout(() => {
                  startListening();
                }, 400);
              }
            };

            audio.onerror = () => {
              const res = ttsService.speakWebSpeech(spokenAnswer, () => {
                setVoiceState("idle");
                setStatusMessage("Sẵn sàng lắng nghe tiếp...");
                if (isHandsFree) {
                  setTimeout(() => startListening(), 400);
                }
              });
              nativeCancelRef.current = res.cancel;
            };

            await audio.play();
          } catch {
            const res = ttsService.speakWebSpeech(spokenAnswer, () => {
              setVoiceState("idle");
              setStatusMessage("Sẵn sàng lắng nghe tiếp...");
              if (isHandsFree) {
                setTimeout(() => startListening(), 400);
              }
            });
            nativeCancelRef.current = res.cancel;
          }
        } else {
          setVoiceState("idle");
          setStatusMessage("Đã nhận câu trả lời.");
          if (isHandsFree) {
            setTimeout(() => startListening(), 600);
          }
        }
      } catch {
        setVoiceState("idle");
        setStatusMessage("Lỗi kết nối khi gửi giọng nói.");
      }
    },
    [stopRecording, onSendMessage, autoSpeak, isHandsFree, startListening]
  );

  // Auto silence commit in hands-free mode
  useEffect(() => {
    if (!isRecording || voiceState !== "listening") return;

    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
    }

    if (transcript && transcript.trim().length > 1) {
      // If user pauses for 1.8s, automatically submit speech
      silenceTimerRef.current = setTimeout(() => {
        commitSpeech(transcript);
      }, 1800);
    }

    return () => {
      if (silenceTimerRef.current) {
        clearTimeout(silenceTimerRef.current);
      }
    };
  }, [transcript, isRecording, voiceState, commitSpeech]);

  // Update status on chat loading
  useEffect(() => {
    if (isLoadingChat && voiceState !== "thinking" && voiceState !== "speaking") {
      setVoiceState("thinking");
      setStatusMessage("Đang xử lý yêu cầu du lịch...");
    }
  }, [isLoadingChat, voiceState]);

  // STT error handling
  useEffect(() => {
    if (sttError) {
      setStatusMessage(`Microphone: ${sttError}`);
      setVoiceState("idle");
    }
  }, [sttError]);

  return {
    voiceState,
    isRecording,
    transcript,
    autoSpeak,
    isHandsFree,
    statusMessage,
    startListening,
    stopListening,
    stopAudio,
    toggleAutoSpeak: () => setAutoSpeak((prev) => !prev),
    toggleHandsFree: () => setIsHandsFree((prev) => !prev),
  };
}
