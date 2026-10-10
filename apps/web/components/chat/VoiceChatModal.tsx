"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import { useSpeechToText } from "@/hooks/useSpeechToText";
import { ttsService } from "@/services/tts.service";

interface VoiceChatModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSendMessage: (text: string, mode?: "chat" | "voice") => Promise<string | null | void>;
  isLoadingChat: boolean;
}

type VoiceState = "idle" | "listening" | "thinking" | "speaking";

export function VoiceChatModal({
  isOpen,
  onClose,
  onSendMessage,
  isLoadingChat,
}: VoiceChatModalProps) {
  const [voiceState, setVoiceState] = useState<VoiceState>("idle");
  const [userTranscript, setUserTranscript] = useState("");
  const [aiResponseText, setAiResponseText] = useState("");
  const [isMuted, setIsMuted] = useState(false);
  const [statusMessage, setStatusMessage] = useState("Sẵn sàng lắng nghe bạn...");
  // Tuỳ chọn bộ phát: 'blaze' (Studio chất lượng cao) hoặc 'native' (Web Speech trình duyệt siêu tốc 0ms)
  const [ttsEngine, setTtsEngine] = useState<"blaze" | "native">("blaze");

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const webSpeechCancelRef = useRef<(() => void) | null>(null);
  const silenceTimerRef = useRef<NodeJS.Timeout | null>(null);
  const lastTranscriptRef = useRef("");
  const isOpenRef = useRef(isOpen);
  isOpenRef.current = isOpen;

  const voiceStateRef = useRef<VoiceState>("idle");
  voiceStateRef.current = voiceState;

  // Stop any active audio playback
  const stopAudio = useCallback(() => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
      audioRef.current = null;
    }
    if (webSpeechCancelRef.current) {
      webSpeechCancelRef.current();
      webSpeechCancelRef.current = null;
    }
  }, []);

  const stopAudioRef = useRef(stopAudio);
  stopAudioRef.current = stopAudio;

  const commitUserSpeechRef = useRef<((text: string) => Promise<void>) | null>(null);

  // Handle incoming real-time transcript from STT
  const handleTranscript = useCallback((text: string, isFinal: boolean) => {
    // Nếu AI đang suy nghĩ hoặc đang nói, bỏ qua để không bị tiếng loa phản hồi kích hoạt nhầm
    if (voiceStateRef.current === "thinking" || voiceStateRef.current === "speaking") {
      return;
    }

    if (!text || !text.trim()) return;

    setUserTranscript(text);
    lastTranscriptRef.current = text;
    setVoiceState("listening");

    // Reset silence timer whenever user speaks
    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }

    // Tối ưu độ trễ phát hiện im lặng:
    // Nếu STT trả về isFinal (đã ngắt câu), chốt câu ngay sau 450ms!
    // Nếu câu đang dở, chờ 900ms
    const delay = isFinal ? 450 : 900;
    if (text.trim().length >= 2) {
      silenceTimerRef.current = setTimeout(() => {
        commitUserSpeechRef.current?.(lastTranscriptRef.current);
      }, delay);
    }
  }, []);

  const {
    isRecording,
    error: sttError,
    startRecording,
    stopRecording,
  } = useSpeechToText({
    onTranscript: handleTranscript,
  });

  const startRecordingRef = useRef(startRecording);
  startRecordingRef.current = startRecording;
  const stopRecordingRef = useRef(stopRecording);
  stopRecordingRef.current = stopRecording;

  // Commit user speech -> Ask Chat API with mode="voice" -> Synthesize TTS -> Play audio
  const commitUserSpeech = useCallback(
    async (textToSend: string) => {
      const trimmed = textToSend.trim();
      if (!trimmed || !isOpenRef.current) return;

      if (silenceTimerRef.current) {
        clearTimeout(silenceTimerRef.current);
        silenceTimerRef.current = null;
      }

      // Tắt microphone trong lúc AI suy nghĩ & trả lời để chống vang âm/ngắt tiếng
      stopRecordingRef.current?.();
      stopAudioRef.current?.();

      setVoiceState("thinking");
      setStatusMessage("AI đang chuẩn bị câu trả lời...");

      try {
        // Gửi với mode="voice" để LLM trả về ngắn gọn (2-3 câu), không markdown, sinh siêu nhanh (<0.5s)
        const responseText = await onSendMessage(trimmed, "voice");

        if (!isOpenRef.current) return;

        if (responseText && typeof responseText === "string") {
          // Làm sạch văn bản để hiển thị và đọc
          const cleanAnswer = ttsService.cleanText(responseText);
          setAiResponseText(cleanAnswer);
          setVoiceState("speaking");
          setStatusMessage("TravelWise đang trả lời...");

          const handleFinishSpeaking = () => {
            if (!isOpenRef.current) return;
            // Khi AI nói xong, tự động mở lại micro lắng nghe ngay lập tức!
            setUserTranscript("");
            lastTranscriptRef.current = "";
            setVoiceState("listening");
            setStatusMessage("Đang lắng nghe câu hỏi tiếp theo của bạn...");
            startRecordingRef.current?.();
          };

          if (ttsEngine === "native") {
            // Chế độ siêu tốc: Dùng Web Speech API của trình duyệt (Độ trễ 0ms)
            const { cancel } = ttsService.speakWebSpeech(
              cleanAnswer,
              handleFinishSpeaking,
              handleFinishSpeaking
            );
            webSpeechCancelRef.current = cancel;
          } else {
            // Chế độ Blaze AI: Stream trực tiếp từ Blaze TTS Realtime WebSocket (TTFB < 500ms)
            try {
              const streamUrl = cleanAnswer.length <= 1800
                ? ttsService.getStreamUrl(cleanAnswer)
                : await ttsService.synthesize(cleanAnswer);

              if (!isOpenRef.current) return;

              const audio = new Audio(streamUrl);
              audio.preload = "auto";
              audioRef.current = audio;

              audio.onended = () => {
                handleFinishSpeaking();
              };

              audio.onerror = () => {
                if (!isOpenRef.current) return;
                // Nếu Blaze audio lỗi phát, fallback tức thì sang Web Speech
                const { cancel } = ttsService.speakWebSpeech(
                  cleanAnswer,
                  handleFinishSpeaking,
                  handleFinishSpeaking
                );
                webSpeechCancelRef.current = cancel;
              };

              await audio.play().catch((playErr) => {
                console.warn("Audio play() blocked, fallback to Web Speech:", playErr);
                const { cancel } = ttsService.speakWebSpeech(
                  cleanAnswer,
                  handleFinishSpeaking,
                  handleFinishSpeaking
                );
                webSpeechCancelRef.current = cancel;
              });
            } catch (ttsErr) {
              console.warn("Blaze TTS failed, falling back to Web Speech:", ttsErr);
              const { cancel } = ttsService.speakWebSpeech(
                cleanAnswer,
                handleFinishSpeaking,
                handleFinishSpeaking
              );
              webSpeechCancelRef.current = cancel;
            }
          }
        } else {
          setVoiceState("listening");
          setStatusMessage("Hãy thử đặt câu hỏi khác...");
          startRecordingRef.current?.();
        }
      } catch (err) {
        console.error("Voice conversation cycle error:", err);
        setVoiceState("listening");
        setStatusMessage("Đã xảy ra lỗi, vui lòng thử lại...");
        startRecordingRef.current?.();
      }
    },
    [onSendMessage, ttsEngine]
  );

  commitUserSpeechRef.current = commitUserSpeech;

  // Manual trigger if user wants to send immediately without waiting for silence
  const handleManualSend = () => {
    if (userTranscript.trim()) {
      commitUserSpeech(userTranscript);
    }
  };

  // Toggle Mute / Mic
  const handleToggleMute = () => {
    if (isRecording) {
      stopRecordingRef.current?.();
      setIsMuted(true);
      setVoiceState("idle");
      setStatusMessage("Microphone đang tắt (Tạm dừng). Bấm để tiếp tục.");
    } else {
      setIsMuted(false);
      setVoiceState("listening");
      setStatusMessage("Đang lắng nghe câu hỏi của bạn...");
      startRecordingRef.current?.();
    }
  };

  // Interrupt AI speaking
  const handleInterruptSpeaking = () => {
    stopAudioRef.current?.();
    setUserTranscript("");
    lastTranscriptRef.current = "";
    setVoiceState("listening");
    setStatusMessage("Đã dừng AI. Mời bạn nói tiếp...");
    startRecordingRef.current?.();
  };

  // Open / Close lifecycle - chỉ chạy khi trạng thái isOpen thay đổi!
  useEffect(() => {
    if (isOpen) {
      setUserTranscript("");
      setAiResponseText("");
      lastTranscriptRef.current = "";
      setIsMuted(false);
      setVoiceState("listening");
      setStatusMessage("TravelWise Voice đã sẵn sàng. Hãy nói điều bạn muốn hỏi!");

      const timer = setTimeout(() => {
        startRecordingRef.current?.();
      }, 250);

      return () => {
        clearTimeout(timer);
        stopRecordingRef.current?.();
        stopAudioRef.current?.();
        if (silenceTimerRef.current) {
          clearTimeout(silenceTimerRef.current);
          silenceTimerRef.current = null;
        }
      };
    } else {
      stopRecordingRef.current?.();
      stopAudioRef.current?.();
      if (silenceTimerRef.current) {
        clearTimeout(silenceTimerRef.current);
        silenceTimerRef.current = null;
      }
      setVoiceState("idle");
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex flex-col justify-between bg-slate-950/95 backdrop-blur-2xl text-slate-100 overflow-hidden animate-in fade-in duration-300">
      {/* Background Ambient Glows */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-teal-500/10 rounded-full blur-3xl pointer-events-none"></div>
      <div className="absolute bottom-1/4 left-1/2 -translate-x-1/2 translate-y-1/2 w-[450px] h-[450px] bg-emerald-500/10 rounded-full blur-3xl pointer-events-none"></div>

      {/* Top Navigation Bar */}
      <header className="relative z-10 flex items-center justify-between px-6 py-4 max-w-4xl w-full mx-auto">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-900/80 border border-slate-800 text-xs font-medium backdrop-blur-md shadow-md">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </span>
            <span className="text-slate-200">TravelWise Voice Call</span>
          </div>

          {/* Engine Selector: Blaze AI Studio vs Trình duyệt Siêu tốc */}
          <div className="flex items-center bg-slate-900/90 border border-slate-800 rounded-full p-0.5 text-[11px]">
            <button
              onClick={() => setTtsEngine("blaze")}
              className={`px-2.5 py-1 rounded-full transition-all cursor-pointer font-medium ${
                ttsEngine === "blaze"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-slate-200"
              }`}
              title="Giọng đọc tiếng Việt tự nhiên qua Blaze AI"
            >
              Blaze AI HD
            </button>
            <button
              onClick={() => setTtsEngine("native")}
              className={`px-2.5 py-1 rounded-full transition-all cursor-pointer font-medium ${
                ttsEngine === "native"
                  ? "bg-emerald-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-slate-200"
              }`}
              title="Phát giọng đọc siêu tốc 0ms từ trình duyệt"
            >
              ⚡ Siêu tốc (0ms)
            </button>
          </div>
        </div>

        {/* Exit Button */}
        <button
          onClick={onClose}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-900/80 hover:bg-slate-800 border border-slate-800 text-xs text-slate-300 hover:text-white transition-all cursor-pointer shadow-lg active:scale-95"
          title="Đóng chế độ giọng nói (Quay lại chat văn bản)"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
          <span className="hidden sm:inline">Thoát Voice Mode</span>
        </button>
      </header>

      {/* Center Interactive Area with Living Voice Orb */}
      <main className="relative z-10 flex-1 flex flex-col items-center justify-center px-4 max-w-xl w-full mx-auto my-auto text-center">
        {/* Animated Voice Orb */}
        <div className="relative flex items-center justify-center my-6">
          {/* Outer Ripple Wave Rings */}
          {voiceState === "listening" && (
            <>
              <div className="absolute w-64 h-64 rounded-full border border-teal-500/20 animate-ping opacity-40 pointer-events-none"></div>
              <div className="absolute w-80 h-80 rounded-full border border-emerald-500/15 animate-pulse opacity-50 pointer-events-none"></div>
            </>
          )}

          {voiceState === "speaking" && (
            <>
              <div className="absolute w-72 h-72 rounded-full bg-cyan-500/20 blur-2xl animate-pulse pointer-events-none"></div>
              <div className="absolute w-88 h-88 rounded-full border border-cyan-500/30 animate-ping opacity-30 pointer-events-none"></div>
            </>
          )}

          {voiceState === "thinking" && (
            <div className="absolute w-64 h-64 rounded-full bg-gradient-to-r from-amber-500/20 to-teal-500/20 blur-2xl animate-spin [animation-duration:6s] pointer-events-none"></div>
          )}

          {/* Central Living Sphere */}
          <div
            onClick={voiceState === "speaking" ? handleInterruptSpeaking : handleToggleMute}
            className={`relative flex items-center justify-center w-40 h-40 sm:w-48 sm:h-48 rounded-full shadow-2xl transition-all duration-700 cursor-pointer select-none group ${voiceState === "speaking"
                ? "bg-gradient-to-tr from-cyan-500 via-teal-400 to-emerald-400 shadow-cyan-500/40 scale-105"
                : voiceState === "thinking"
                  ? "bg-gradient-to-tr from-teal-500 via-amber-400 to-emerald-500 shadow-teal-500/40 animate-pulse scale-95"
                  : voiceState === "listening"
                    ? "bg-gradient-to-tr from-teal-400 to-emerald-500 shadow-teal-500/50 scale-100"
                    : "bg-slate-800 text-slate-500 border border-slate-700 shadow-slate-900/50 scale-95"
              }`}
          >
            {/* Inner Graphic Elements */}
            {voiceState === "speaking" ? (
              /* Sound Equalizer Waves */
              <div className="flex items-center gap-1.5 h-12">
                <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.4s] h-6"></span>
                <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.2s] h-10"></span>
                <span className="w-1.5 bg-slate-950 rounded-full animate-bounce h-12"></span>
                <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.1s] h-9"></span>
                <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.3s] h-7"></span>
              </div>
            ) : voiceState === "thinking" ? (
              /* Thinking Spinner */
              <div className="flex items-center justify-center">
                <svg className="w-12 h-12 text-slate-950 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
                </svg>
              </div>
            ) : voiceState === "listening" ? (
              /* Microphone Icon with gentle pulse */
              <svg className="w-14 h-14 text-slate-950 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              </svg>
            ) : (
              /* Muted / Idle Mic Icon */
              <svg className="w-12 h-12 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
              </svg>
            )}
          </div>
        </div>

        {/* Dynamic Status Title */}
        <p className="text-sm font-medium text-slate-300 mt-2 transition-all">
          {statusMessage}
        </p>

        {/* Live Subtitle Transcript Card */}
        <div className="w-full mt-6 min-h-[90px] max-h-36 overflow-y-auto px-4 py-3 rounded-2xl bg-slate-900/70 border border-slate-800/80 backdrop-blur-xl shadow-xl flex flex-col justify-center transition-all">
          {voiceState === "speaking" && aiResponseText ? (
            <div className="text-left animate-in fade-in">
              <span className="text-[10px] uppercase font-bold text-teal-400 tracking-wider">TravelWise AI</span>
              <p className="text-sm text-slate-100 line-clamp-3 mt-0.5 leading-relaxed font-normal">
                {aiResponseText}
              </p>
            </div>
          ) : userTranscript ? (
            <div className="text-left animate-in fade-in">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Bạn đang nói</span>
              <p className="text-sm text-teal-200 line-clamp-3 mt-0.5 leading-relaxed font-medium">
                “{userTranscript}”
              </p>
            </div>
          ) : (
            <p className="text-xs text-slate-500 italic">
              Hãy hỏi những gì bạn tò mò về địa điểm, đồ ăn ngon hoặc lịch trình du lịch...
            </p>
          )}
        </div>

        {/* STT Error Notification */}
        {sttError && (
          <p className="mt-2 text-xs text-amber-400 font-medium">
            ⚠️ {sttError}
          </p>
        )}
      </main>

      {/* Bottom Floating Control Bar */}
      <footer className="relative z-10 pb-8 pt-4 px-6 max-w-md w-full mx-auto flex items-center justify-center gap-4">
        {/* Toggle Mute / Mic Button */}
        <button
          onClick={handleToggleMute}
          className={`flex items-center justify-center w-14 h-14 rounded-2xl shadow-xl transition-all duration-200 active:scale-95 cursor-pointer ${isMuted || !isRecording
              ? "bg-slate-800 text-slate-400 border border-slate-700 hover:text-white"
              : "bg-teal-500/20 text-teal-400 border border-teal-500/50 shadow-teal-500/20 hover:bg-teal-500/30"
            }`}
          title={isMuted ? "Bật microphone" : "Tắt microphone"}
        >
          {isMuted || !isRecording ? (
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              <line x1="3" y1="3" x2="21" y2="21" stroke="currentColor" strokeWidth="2" />
            </svg>
          ) : (
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          )}
        </button>

        {/* Center Dynamic Action: Send Speech or Stop Speaking */}
        {voiceState === "speaking" ? (
          <button
            onClick={handleInterruptSpeaking}
            className="flex items-center gap-2 px-5 h-14 rounded-2xl bg-red-500/20 text-red-300 border border-red-500/50 shadow-lg shadow-red-500/20 hover:bg-red-500/30 active:scale-95 transition-all cursor-pointer font-medium text-sm"
            title="Dừng AI nói và chuyển sang lượt bạn"
          >
            <span className="w-3 h-3 rounded-sm bg-red-400"></span>
            <span>Dừng nói</span>
          </button>
        ) : (
          <button
            onClick={handleManualSend}
            disabled={!userTranscript.trim() || voiceState === "thinking"}
            className={`flex items-center gap-2 px-6 h-14 rounded-2xl shadow-xl transition-all duration-200 font-medium text-sm ${userTranscript.trim() && voiceState !== "thinking"
                ? "bg-gradient-to-r from-teal-500 to-emerald-400 text-slate-950 shadow-teal-500/30 hover:scale-105 active:scale-95 cursor-pointer"
                : "bg-slate-900 text-slate-600 border border-slate-800 cursor-not-allowed"
              }`}
            title="Gửi câu hỏi ngay"
          >
            <span>Gửi câu hỏi</span>
            <svg className="w-4 h-4 translate-x-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.5" d="M14 5l7 7m0 0l-7 7m7-7H3" />
            </svg>
          </button>
        )}

        {/* Close Button */}
        <button
          onClick={onClose}
          className="flex items-center justify-center w-14 h-14 rounded-2xl bg-slate-900 border border-slate-800 text-slate-400 hover:text-rose-400 hover:border-rose-500/40 shadow-xl transition-all active:scale-95 cursor-pointer"
          title="Kết thúc cuộc gọi thoại"
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </footer>
    </div>
  );
}
