"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  LiveKitRoom,
  RoomAudioRenderer,
  useConnectionState,
  useLocalParticipant,
  useRemoteParticipants,
  useRoomContext,
  useSpeakingParticipants,
} from "@livekit/components-react";
import { ConnectionState, RoomEvent } from "livekit-client";
import { livekitService } from "@/services/livekit.service";
import { LiveKitConnectionStatus, LiveKitTokenResponse } from "@/types/livekit";
import { ApiError } from "@/services/api";

export type VoiceCompanionState =
  | "connecting"
  | "listening"
  | "analyzing"
  | "speaking"
  | "ready"
  | "muted";

interface LiveKitVoicePanelProps {
  conversationId?: number | null;
  roomName?: string | null;
  autoConnect?: boolean;
  onSessionStarted?: (data: LiveKitTokenResponse) => void;
  onSessionEnded?: () => void;
  onSendMessage?: (text: string) => Promise<string | null | void>;
  latestUserText?: string;
  latestAssistantText?: string;
}

const QUICK_SUGGESTIONS = [
  "Lên lịch trình 3 ngày 2 đêm tại Đà Nẵng",
  "Món ngon đặc sản Hội An không nên bỏ lỡ",
  "Kinh nghiệm đi Bà Nà Hills tự túc tiết kiệm",
];

/**
 * Child controller component inside LiveKitRoom context
 * Pure voice companion interface (Living Voice Orb, zero debug clutter)
 */
function RoomController({
  onDisconnect,
  onSendMessage,
  latestUserText,
  latestAssistantText,
}: {
  onDisconnect: () => void;
  onSendMessage?: (text: string) => Promise<string | null | void>;
  latestUserText?: string;
  latestAssistantText?: string;
}) {
  const room = useRoomContext();
  const connectionState = useConnectionState();
  const { localParticipant, isMicrophoneEnabled } = useLocalParticipant();
  const remoteParticipants = useRemoteParticipants();
  const speakingParticipants = useSpeakingParticipants();

  const [isTogglingMic, setIsTogglingMic] = useState(false);
  const [isDisconnecting, setIsDisconnecting] = useState(false);
  const [micError, setMicError] = useState<string | null>(null);

  // Check speech activity via WebRTC audio stream detectors
  const isAgentSpeaking = remoteParticipants.some((p) => p.isSpeaking);
  const isUserSpeaking = Boolean(localParticipant?.isSpeaking);

  // States for 3-stage Voice Flow: Đang nghe -> Đang phân tích -> Đang trả lời
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [agentStatusText, setAgentStatusText] = useState<string | null>(null);
  const wasUserSpeakingRef = useRef(false);
  const analyzingTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Real-time bidirectional speech transcripts & conversation history
  const [userTranscript, setUserTranscript] = useState<string>("");
  const [aiTranscript, setAiTranscript] = useState<string>(
    "Chào bạn! Tôi là TravelWise AI. Bạn muốn khám phá địa điểm hay lên lịch trình du lịch nào hôm nay?"
  );
  const [conversationHistory, setConversationHistory] = useState<
    Array<{ id: number; role: "user" | "assistant"; text: string; timestamp: number }>
  >([]);
  const [showHistoryModal, setShowHistoryModal] = useState<boolean>(false);
  const recognitionRef = useRef<any>(null);

  // Reactive transition: When user finishes speaking -> transition to "analyzing"
  useEffect(() => {
    if (isUserSpeaking) {
      wasUserSpeakingRef.current = true;
      setIsAnalyzing(false);
      if (analyzingTimeoutRef.current) {
        clearTimeout(analyzingTimeoutRef.current);
        analyzingTimeoutRef.current = null;
      }
    } else if (wasUserSpeakingRef.current && !isAgentSpeaking) {
      // User just stopped speaking, AI starts analyzing
      wasUserSpeakingRef.current = false;
      setIsAnalyzing(true);

      // Auto fallback if no response arrives within 15 seconds
      if (analyzingTimeoutRef.current) clearTimeout(analyzingTimeoutRef.current);
      analyzingTimeoutRef.current = setTimeout(() => {
        setIsAnalyzing(false);
      }, 15000);
    }
  }, [isUserSpeaking, isAgentSpeaking]);

  // Track AI speaking state and timestamp to prevent microphone from transcribing speaker audio (acoustic echo feedback)
  const isAgentSpeakingRef = useRef(false);
  const lastAgentSpokeTimeRef = useRef(0);

  // When AI starts speaking, stop analyzing and record timestamp
  useEffect(() => {
    isAgentSpeakingRef.current = isAgentSpeaking;
    if (isAgentSpeaking) {
      lastAgentSpokeTimeRef.current = Date.now();
      setIsAnalyzing(false);
      wasUserSpeakingRef.current = false;
      if (analyzingTimeoutRef.current) {
        clearTimeout(analyzingTimeoutRef.current);
        analyzingTimeoutRef.current = null;
      }
    } else {
      lastAgentSpokeTimeRef.current = Date.now();
    }
  }, [isAgentSpeaking]);

  // Sync external messages from chat/RAG if provided
  useEffect(() => {
    if (latestUserText) {
      setUserTranscript(latestUserText);
      // Khi có câu hỏi mới của người dùng, reset câu trả lời cũ của AI
      setAiTranscript("");
    }
  }, [latestUserText]);

  useEffect(() => {
    if (latestAssistantText !== undefined && latestAssistantText !== null) {
      setAiTranscript(latestAssistantText);
    }
  }, [latestAssistantText]);

  // Browser-side Live Speech-to-Text Recognition (Captures user speech in real-time)
  useEffect(() => {
    if (typeof window === "undefined") return;
    const SpeechRecognition =
      (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;

    if (!SpeechRecognition) return;

    if (!localParticipant || !isMicrophoneEnabled) {
      if (recognitionRef.current) {
        try {
          recognitionRef.current.stop();
        } catch {}
        recognitionRef.current = null;
      }
      return;
    }

    let recognition: any = null;
    let isStoppedManually = false;

    try {
      recognition = new SpeechRecognition();
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = "vi-VN";

      recognition.onresult = (event: any) => {
        // Acoustic Echo Cancellation: If AI is speaking or just finished within 1.2s,
        // ignore microphone input so computer speaker audio doesn't get transcribed as user speech!
        const timeSinceAgentSpoke = Date.now() - lastAgentSpokeTimeRef.current;
        if (isAgentSpeakingRef.current || (lastAgentSpokeTimeRef.current > 0 && timeSinceAgentSpoke < 1200)) {
          return;
        }

        let interimText = "";
        let finalChunk = "";

        for (let i = event.resultIndex; i < event.results.length; ++i) {
          const item = event.results[i];
          if (item.isFinal) {
            finalChunk += item[0].transcript;
          } else {
            interimText += item[0].transcript;
          }
        }

        const currentText = (finalChunk || interimText).trim();
        if (currentText) {
          setUserTranscript(currentText);
          if (finalChunk.trim()) {
            const trimmed = finalChunk.trim();
            // Xóa ngay câu trả lời cũ của AI để câu trả lời mới được sinh ra bên dưới
            setAiTranscript("");
            setIsAnalyzing(true);
            setConversationHistory((prev) => {
              const last = prev[prev.length - 1];
              if (last && last.role === "user" && last.text === trimmed) {
                return prev;
              }
              return [
                ...prev,
                { id: Date.now(), role: "user", text: trimmed, timestamp: Date.now() },
              ];
            });

            // If onSendMessage is provided, ask LLM
            if (onSendMessage) {
              onSendMessage(trimmed)
                .then((res) => {
                  if (res && typeof res === "string") {
                    setAiTranscript(res);
                    setIsAnalyzing(false);
                    setConversationHistory((prev) => [
                      ...prev,
                      { id: Date.now(), role: "assistant", text: res, timestamp: Date.now() },
                    ]);
                  }
                })
                .catch((e) => {
                  console.warn("Lỗi khi gửi tin nhắn thoại lên LLM:", e);
                  setIsAnalyzing(false);
                });
            }
          }
        }
      };

      recognition.onerror = (e: any) => {
        if (e.error !== "no-speech" && e.error !== "aborted") {
          console.debug("Speech recognition event:", e.error);
        }
      };

      recognition.onend = () => {
        if (!isStoppedManually && isMicrophoneEnabled) {
          try {
            recognition.start();
          } catch {}
        }
      };

      recognition.start();
      recognitionRef.current = recognition;
    } catch (err) {
      console.debug("SpeechRecognition initialization skipped:", err);
    }

    return () => {
      isStoppedManually = true;
      if (recognition) {
        try {
          recognition.stop();
        } catch {}
      }
      recognitionRef.current = null;
    };
  }, [localParticipant, isMicrophoneEnabled, onSendMessage]);

  // Clean up timer on unmount
  useEffect(() => {
    return () => {
      if (analyzingTimeoutRef.current) {
        clearTimeout(analyzingTimeoutRef.current);
      }
    };
  }, []);

  // Listen to custom data packets from the backend agent
  useEffect(() => {
    if (!room) return;

    const handleDataReceived = (payload: Uint8Array) => {
      try {
        const text = new TextDecoder().decode(payload);
        const data = JSON.parse(text);
        if (data.type === "state") {
          if (data.state === "analyzing" || data.state === "thinking") {
            setIsAnalyzing(true);
            if (data.text) setAgentStatusText(data.text);
          } else if (data.state === "speaking") {
            setIsAnalyzing(false);
            if (data.text) setAgentStatusText(data.text);
          } else if (data.state === "ready" || data.state === "idle") {
            setIsAnalyzing(false);
            setAgentStatusText(null);
          }
        } else if (data.type === "transcript" || data.type === "text") {
          const role = data.role === "user" ? "user" : "assistant";
          const messageText = data.text || "";
          if (role === "user") {
            setUserTranscript(messageText);
            setAiTranscript(""); // Xóa câu trả lời cũ của AI để câu trả lời mới xuất hiện bên dưới
            setIsAnalyzing(true);
            setConversationHistory((prev) => [
              ...prev,
              { id: Date.now(), role: "user", text: messageText, timestamp: Date.now() },
            ]);
          } else {
            setAiTranscript(messageText);
            setIsAnalyzing(false);
            setConversationHistory((prev) => [
              ...prev,
              { id: Date.now(), role: "assistant", text: messageText, timestamp: Date.now() },
            ]);
          }
        }
      } catch {
        // Not a JSON packet, ignore
      }
    };

    room.on(RoomEvent.DataReceived, handleDataReceived);
    return () => {
      room.off(RoomEvent.DataReceived, handleDataReceived);
    };
  }, [room]);

  // Explicitly disconnect room and turn off microphone hardware
  const handleDisconnectClick = useCallback(async () => {
    setIsDisconnecting(true);
    try {
      if (localParticipant) {
        await localParticipant.setMicrophoneEnabled(false);
      }
      if (room) {
        await room.disconnect();
      }
    } catch (err) {
      console.warn("Lỗi khi ngắt kết nối LiveKit room:", err);
    } finally {
      onDisconnect();
    }
  }, [localParticipant, room, onDisconnect]);

  // Handle toggle microphone with browser permission error handling
  const handleToggleMic = useCallback(async () => {
    if (!localParticipant) return;
    setIsTogglingMic(true);
    setMicError(null);

    const targetState = !isMicrophoneEnabled;
    try {
      await localParticipant.setMicrophoneEnabled(targetState);
    } catch (err: unknown) {
      let errMsg = "Không thể truy cập microphone.";
      if (err instanceof DOMException) {
        if (err.name === "NotAllowedError" || err.name === "PermissionDeniedError") {
          errMsg = "Quyền truy cập microphone bị từ chối. Hãy cho phép micro trong cài đặt trình duyệt.";
        } else if (err.name === "NotFoundError" || err.name === "DevicesNotFoundError") {
          errMsg = "Không tìm thấy thiết bị microphone nào trên máy của bạn.";
        } else if (err.name === "NotReadableError" || err.name === "TrackStartError") {
          errMsg = "Microphone đang bị chiếm dụng bởi ứng dụng khác.";
        }
      }
      setMicError(errMsg);
    } finally {
      setIsTogglingMic(false);
    }
  }, [localParticipant, isMicrophoneEnabled]);

  const isConnected = connectionState === ConnectionState.Connected;

  // Determine current active voice state for UI animations
  const voiceState: VoiceCompanionState = !isConnected
    ? "connecting"
    : isAgentSpeaking
    ? "speaking"
    : isAnalyzing
    ? "analyzing"
    : isUserSpeaking
    ? "listening"
    : !isMicrophoneEnabled
    ? "muted"
    : "ready";

  return (
    <div className="flex flex-col items-center text-center w-full max-w-xl mx-auto pt-2 pb-8 animate-in fade-in duration-300">
      {/* Top Status Pill */}
      <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-slate-900/80 border border-slate-800 backdrop-blur-md shadow-lg mb-4">
        <span className="relative flex h-2 w-2">
          {voiceState === "speaking" ? (
            <>
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-cyan-500"></span>
            </>
          ) : voiceState === "analyzing" ? (
            <>
              <span className="animate-spin absolute inline-flex h-full w-full rounded-full border border-amber-400 border-t-transparent"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-amber-400"></span>
            </>
          ) : voiceState === "listening" ? (
            <>
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </>
          ) : (
            <span className="relative inline-flex rounded-full h-2 w-2 bg-teal-400"></span>
          )}
        </span>
        <span className="text-xs font-medium text-slate-200">
          {voiceState === "speaking"
            ? "TravelWise AI đang trả lời"
            : voiceState === "analyzing"
            ? "AI đang phân tích câu trả lời..."
            : voiceState === "listening"
            ? "Đang lắng nghe bạn nói"
            : voiceState === "muted"
            ? "Microphone đang tắt tiếng"
            : "LiveKit WebRTC • Sẵn sàng đàm thoại"}
        </span>
      </div>

      {/* 3-State Visual Indicator Pipeline: [Đang nghe] -> [Đang phân tích] -> [Đang trả lời] */}
      <div className="flex items-center justify-center gap-1.5 sm:gap-2 mb-4 select-none">
        {/* State 1: Đang nghe */}
        <div
          className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all duration-300 ${
            voiceState === "listening"
              ? "bg-emerald-500/20 text-emerald-300 border border-emerald-500/50 shadow-lg shadow-emerald-500/20 scale-105"
              : "bg-slate-900/50 text-slate-500 border border-slate-800/80"
          }`}
        >
          <span className={voiceState === "listening" ? "animate-bounce text-sm" : "opacity-50"}>🎙️</span>
          <span>Đang nghe</span>
        </div>

        <span className="text-slate-600 text-xs">→</span>

        {/* State 2: Đang phân tích */}
        <div
          className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all duration-300 ${
            voiceState === "analyzing"
              ? "bg-amber-500/20 text-amber-300 border border-amber-500/50 shadow-lg shadow-amber-500/20 scale-105"
              : "bg-slate-900/50 text-slate-500 border border-slate-800/80"
          }`}
        >
          <span className={voiceState === "analyzing" ? "animate-spin text-sm" : "opacity-50"}>🧠</span>
          <span>Đang phân tích</span>
        </div>

        <span className="text-slate-600 text-xs">→</span>

        {/* State 3: Đang trả lời */}
        <div
          className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all duration-300 ${
            voiceState === "speaking"
              ? "bg-cyan-500/20 text-cyan-300 border border-cyan-500/50 shadow-lg shadow-cyan-500/20 scale-105"
              : "bg-slate-900/50 text-slate-500 border border-slate-800/80"
          }`}
        >
          <span className={voiceState === "speaking" ? "animate-pulse text-sm" : "opacity-50"}>🔊</span>
          <span>Đang trả lời</span>
        </div>
      </div>

      {/* Living Voice Orb (Centerpiece) */}
      <div className="relative flex items-center justify-center my-4 sm:my-6">
        {/* Outer Ripple Wave Rings when Speaking, Listening, or Analyzing */}
        {voiceState === "listening" && (
          <>
            <div className="absolute w-64 h-64 sm:w-72 sm:h-72 rounded-full border border-emerald-500/30 animate-ping opacity-50 pointer-events-none" />
            <div className="absolute w-80 h-80 sm:w-96 sm:h-96 rounded-full border border-teal-500/20 animate-pulse opacity-60 pointer-events-none" />
          </>
        )}

        {voiceState === "analyzing" && (
          <>
            <div className="absolute w-72 h-72 sm:w-88 sm:h-88 rounded-full bg-gradient-to-tr from-amber-500/20 via-purple-500/25 to-teal-500/20 blur-3xl animate-spin [animation-duration:8s] pointer-events-none" />
            <div className="absolute w-84 h-84 sm:w-96 sm:h-96 rounded-full border border-amber-400/30 animate-pulse opacity-50 pointer-events-none" />
          </>
        )}

        {voiceState === "speaking" && (
          <>
            <div className="absolute w-72 h-72 sm:w-88 sm:h-88 rounded-full bg-cyan-500/20 blur-3xl animate-pulse pointer-events-none" />
            <div className="absolute w-88 h-88 sm:w-[420px] sm:h-[420px] rounded-full border border-cyan-400/30 animate-ping opacity-40 pointer-events-none" />
          </>
        )}

        {voiceState === "ready" && (
          <div className="absolute w-64 h-64 rounded-full bg-teal-500/15 blur-2xl animate-pulse pointer-events-none" />
        )}

        {/* Central Living Sphere (Click to toggle Mic) */}
        <button
          type="button"
          onClick={handleToggleMic}
          className={`relative flex items-center justify-center w-40 h-40 sm:w-52 sm:h-52 rounded-full shadow-2xl transition-all duration-700 cursor-pointer select-none group active:scale-95 ${
            voiceState === "speaking"
              ? "bg-gradient-to-tr from-cyan-500 via-teal-400 to-emerald-400 shadow-cyan-500/50 scale-105"
              : voiceState === "analyzing"
              ? "bg-gradient-to-tr from-amber-500 via-purple-500 to-teal-400 shadow-amber-500/50 animate-pulse scale-100 ring-4 ring-amber-500/25"
              : voiceState === "listening"
              ? "bg-gradient-to-tr from-emerald-400 via-teal-400 to-cyan-500 shadow-emerald-500/60 scale-100 ring-4 ring-emerald-500/25"
              : voiceState === "muted"
              ? "bg-slate-800 text-slate-500 border border-slate-700 shadow-slate-900/50 scale-95"
              : "bg-gradient-to-tr from-teal-500 via-teal-400 to-emerald-500 shadow-teal-500/50 hover:scale-102"
          }`}
          title={isMicrophoneEnabled ? "Nhấn để tắt micro" : "Nhấn để bật micro"}
        >
          {voiceState === "speaking" ? (
            /* Equalizer Sound Waves when AI speaks */
            <div className="flex items-center gap-1.5 h-12">
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.4s] h-6" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.2s] h-10" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce h-12" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.1s] h-9" />
              <span className="w-1.5 bg-slate-950 rounded-full animate-bounce [animation-delay:-0.3s] h-7" />
            </div>
          ) : voiceState === "analyzing" ? (
            /* Thinking / Analyzing Neural Spinner */
            <div className="relative flex items-center justify-center">
              <svg className="w-16 h-16 sm:w-20 sm:h-20 text-slate-950 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" />
                <path className="opacity-80" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
              </svg>
              <span className="absolute text-2xl sm:text-3xl select-none animate-pulse">🧠</span>
            </div>
          ) : voiceState === "listening" ? (
            /* Active Microphone icon with pulse */
            <svg className="w-14 h-14 sm:w-16 sm:h-16 text-slate-950 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          ) : voiceState === "muted" ? (
            /* Muted Mic Icon */
            <svg className="w-12 h-12 sm:w-14 sm:h-14 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              <line x1="3" y1="3" x2="21" y2="21" stroke="currentColor" strokeWidth="2" />
            </svg>
          ) : (
            /* Standby Friendly Mic Icon */
            <svg className="w-14 h-14 sm:w-16 sm:h-16 text-slate-950 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          )}
        </button>
      </div>

      {/* Real-time Bidirectional Captions Area (Lời bạn nói ở trên & nội dung AI tạo ra ở dưới) */}
      <div className="w-full max-w-lg mx-auto min-h-[90px] flex flex-col gap-2.5 px-3 sm:px-4 my-2">
        {/* 1. Lời bạn nói (NẰM Ở TRÊN) */}
        {userTranscript ? (
          <div className="p-3 rounded-2xl bg-slate-900/80 border border-emerald-500/35 backdrop-blur-md shadow-lg text-left flex items-start gap-3 animate-in fade-in slide-in-from-bottom-1 duration-200">
            <div className="w-7 h-7 rounded-full bg-emerald-500/20 text-emerald-300 flex items-center justify-center flex-shrink-0 text-xs font-bold ring-1 ring-emerald-500/30 mt-0.5 select-none">
              👤
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between mb-0.5">
                <span className="text-[10px] uppercase font-bold text-emerald-400 tracking-wider">
                  {voiceState === "listening" ? "🎙️ Bạn đang nói..." : "👤 Bạn vừa nói"}
                </span>
                {voiceState === "listening" && (
                  <span className="inline-flex h-2 w-2 rounded-full bg-emerald-400 animate-ping" />
                )}
              </div>
              <p className="text-xs sm:text-sm text-slate-100 font-medium italic leading-relaxed">
                &ldquo;{userTranscript}&rdquo;
              </p>
            </div>
          </div>
        ) : (
          <div className="p-2.5 rounded-2xl bg-slate-900/40 border border-slate-800/60 backdrop-blur-sm text-left flex items-center gap-3">
            <div className="w-7 h-7 rounded-full bg-emerald-500/10 text-emerald-400 flex items-center justify-center flex-shrink-0 text-xs font-bold ring-1 ring-emerald-500/20 select-none">
              👤
            </div>
            <div className="flex-1 min-w-0">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider block">
                👤 Lời bạn nói (Ở trên)
              </span>
              <p className="text-xs text-slate-500 italic">
                {isMicrophoneEnabled
                  ? "Đang lắng nghe... Hãy nói điều gì đó để đặt câu hỏi"
                  : "Bấm vào quả cầu để bật micro và bắt đầu nói"}
              </p>
            </div>
          </div>
        )}

        {/* 2. Nội dung AI tạo ra (NẰM Ở DƯỚI) */}
        {aiTranscript || isAnalyzing || voiceState === "analyzing" || voiceState === "speaking" ? (
          <div className="p-3.5 rounded-2xl bg-gradient-to-r from-slate-900/95 via-teal-950/30 to-slate-900/95 border border-cyan-500/35 backdrop-blur-md shadow-xl text-left flex items-start gap-3 animate-in fade-in slide-in-from-bottom-2 duration-300">
            <div className="w-7 h-7 rounded-full bg-cyan-500/20 text-cyan-300 flex items-center justify-center flex-shrink-0 text-xs font-bold ring-1 ring-cyan-500/30 mt-0.5 select-none">
              🌴
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between mb-1">
                <span className="text-[10px] uppercase font-bold text-cyan-300 tracking-wider">
                  TravelWise AI
                </span>
                {voiceState === "speaking" && (
                  <span className="flex items-center gap-1 text-[10px] text-cyan-400 animate-pulse font-medium">
                    <span>🔊 Đang đọc phản hồi...</span>
                  </span>
                )}
                {(voiceState === "analyzing" || isAnalyzing) && (
                  <span className="flex items-center gap-1 text-[10px] text-amber-300 animate-pulse font-medium">
                    <span>🧠 Đang phân tích...</span>
                  </span>
                )}
              </div>
              {aiTranscript ? (
                <p className="text-xs sm:text-sm text-slate-100 font-normal leading-relaxed">
                  {aiTranscript}
                </p>
              ) : (
                <div className="flex items-center gap-2 py-1 text-teal-300 text-xs sm:text-sm animate-pulse">
                  <span className="inline-block w-2 h-2 rounded-full bg-teal-400 animate-ping" />
                  <span>Đang suy nghĩ câu trả lời cho bạn...</span>
                </div>
              )}
            </div>
          </div>
        ) : (
          <div className="py-2.5 px-3 rounded-2xl bg-slate-900/30 border border-slate-800/40 text-left flex items-center gap-3">
            <div className="w-7 h-7 rounded-full bg-cyan-500/10 text-cyan-400 flex items-center justify-center flex-shrink-0 text-xs font-bold ring-1 ring-cyan-500/20 select-none">
              🌴
            </div>
            <div className="flex-1 min-w-0">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider block">
                TravelWise AI (Ở dưới)
              </span>
              <p className="text-xs text-slate-500">
                Câu trả lời thông minh từ AI sẽ tự động xuất hiện tại đây...
              </p>
            </div>
          </div>
        )}

        {/* Conversation History Drawer Toggle (Khi có trên 1 câu đối thoại) */}
        {conversationHistory.length > 1 && (
          <div className="flex justify-center mt-0.5">
            <button
              type="button"
              onClick={() => setShowHistoryModal((prev) => !prev)}
              className="text-[11px] text-slate-400 hover:text-teal-300 transition-colors flex items-center gap-1.5 cursor-pointer select-none py-1 px-3 rounded-full hover:bg-slate-900/60 border border-slate-800/60"
            >
              <span>📜 {showHistoryModal ? "Thu gọn nhật ký" : `Xem lại toàn bộ hội thoại (${conversationHistory.length} câu)`}</span>
            </button>
          </div>
        )}

        {/* Expanded History Modal List */}
        {showHistoryModal && conversationHistory.length > 0 && (
          <div className="w-full mt-1.5 p-3 rounded-2xl bg-slate-900/95 border border-slate-800 max-h-48 overflow-y-auto text-left space-y-2 custom-scrollbar animate-in fade-in">
            {conversationHistory.map((msg) => (
              <div
                key={msg.id}
                className={`p-2.5 rounded-xl text-xs leading-relaxed ${
                  msg.role === "user"
                    ? "bg-emerald-950/20 border border-emerald-500/20 text-slate-200"
                    : "bg-cyan-950/20 border border-cyan-500/20 text-slate-200"
                }`}
              >
                <div className="font-bold text-[10px] uppercase mb-1 tracking-wider opacity-80">
                  {msg.role === "user" ? "👤 Bạn" : "🌴 TravelWise AI"}
                </div>
                <p>{msg.text}</p>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Quick Suggestion Chips (Bấm vào để hỏi nhanh) */}
      {voiceState === "ready" && (
        <div className="flex flex-wrap items-center justify-center gap-2 mt-2 max-w-md animate-in fade-in">
          {QUICK_SUGGESTIONS.map((item, idx) => (
            <button
              key={idx}
              type="button"
              onClick={() => {
                setUserTranscript(item);
                setIsAnalyzing(true);
                setConversationHistory((prev) => [
                  ...prev,
                  { id: Date.now(), role: "user", text: item, timestamp: Date.now() },
                ]);
              }}
              className="text-xs px-3 py-1.5 rounded-full bg-slate-900/60 hover:bg-slate-800/80 border border-slate-800 hover:border-teal-500/40 text-slate-400 hover:text-teal-300 transition-all cursor-pointer select-none active:scale-95"
            >
              💡 {item}
            </button>
          ))}
        </div>
      )}

      {/* Mic Permission Warning */}
      {micError && (
        <div className="mt-4 p-3 bg-rose-500/10 border border-rose-500/30 rounded-2xl text-rose-300 text-xs flex items-center justify-between max-w-md w-full">
          <span>⚠️ {micError}</span>
          <button
            onClick={() => setMicError(null)}
            className="text-rose-400 hover:text-rose-200 ml-2 font-bold cursor-pointer"
          >
            ✕
          </button>
        </div>
      )}

      {/* Floating Action Buttons */}
      <div className="flex items-center justify-center gap-5 mt-6">
        {/* Toggle Mic Button */}
        <button
          type="button"
          onClick={handleToggleMic}
          disabled={!isConnected || isTogglingMic}
          className={`flex items-center justify-center w-14 h-14 rounded-2xl shadow-xl transition-all duration-200 active:scale-95 cursor-pointer ${
            !isMicrophoneEnabled
              ? "bg-slate-800 text-slate-400 border border-slate-700 hover:text-white"
              : "bg-teal-500/20 text-teal-300 border border-teal-500/50 shadow-teal-500/20 hover:bg-teal-500/30 ring-2 ring-teal-500/20"
          } disabled:opacity-50`}
          title={isMicrophoneEnabled ? "Tắt microphone" : "Bật microphone"}
        >
          {isMicrophoneEnabled ? (
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          ) : (
            <svg className="w-6 h-6 text-rose-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              <line x1="3" y1="3" x2="21" y2="21" stroke="currentColor" strokeWidth="2" />
            </svg>
          )}
        </button>

        {/* End Call Button */}
        <button
          type="button"
          onClick={handleDisconnectClick}
          disabled={isDisconnecting}
          className="flex items-center justify-center w-14 h-14 rounded-2xl bg-rose-600/90 hover:bg-rose-500 text-white shadow-xl shadow-rose-600/30 transition-all duration-200 active:scale-95 cursor-pointer disabled:opacity-50"
          title="Kết thúc cuộc gọi thoại"
        >
          <svg className="w-6 h-6 rotate-[135deg]" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6.62 10.79a15.053 15.053 0 006.59 6.59l2.2-2.2a1 1 0 011.01-.24c1.12.37 2.33.57 3.58.57a1 1 0 011 1V20a1 1 0 01-1 1A17 17 0 013 4a1 1 0 011-1h3.5a1 1 0 011 1c0 1.25.2 2.46.57 3.58a1 1 0 01-.24 1.01l-2.21 2.2z" />
          </svg>
        </button>
      </div>
    </div>
  );
}

/**
 * Main LiveKitVoicePanel Component
 */
export function LiveKitVoicePanel({
  conversationId,
  roomName,
  autoConnect = true,
  onSessionStarted,
  onSessionEnded,
  onSendMessage,
  latestUserText,
  latestAssistantText,
}: LiveKitVoicePanelProps) {
  const [status, setStatus] = useState<LiveKitConnectionStatus>("disconnected");
  const [tokenData, setTokenData] = useState<LiveKitTokenResponse | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const isUnmountedRef = useRef(false);
  const hasAutoConnectedRef = useRef(false);

  useEffect(() => {
    isUnmountedRef.current = false;
    return () => {
      isUnmountedRef.current = true;
    };
  }, []);

  // Connect to LiveKit Room
  const handleConnect = useCallback(async () => {
    hasAutoConnectedRef.current = true;
    setErrorMessage(null);
    setStatus("connecting");

    try {
      let data;
      try {
        data = await livekitService.getRoomToken(conversationId, roomName);
      } catch (tokenErr: unknown) {
        // If 403 Forbidden because this conversation belongs to another user,
        // fallback gracefully by requesting a fresh conversation for current user!
        if (
          tokenErr instanceof ApiError &&
          tokenErr.status === 403 &&
          conversationId !== null
        ) {
          console.warn(
            `Conversation ${conversationId} is forbidden for current user. Creating a new conversation session.`
          );
          data = await livekitService.getRoomToken(null, roomName);
          if (typeof window !== "undefined" && data.conversation_id) {
            const currentUrl = new URL(window.location.href);
            currentUrl.searchParams.set("conversation_id", String(data.conversation_id));
            window.history.replaceState(null, "", currentUrl.toString());
          }
        } else {
          throw tokenErr;
        }
      }

      if (isUnmountedRef.current) return;

      setTokenData(data);
      setStatus("connected");
      onSessionStarted?.(data);
    } catch (err: unknown) {
      if (isUnmountedRef.current) return;
      setStatus("error");
      let msg = "Không thể kết nối máy chủ LiveKit thoại.";
      if (err instanceof ApiError) {
        msg = err.message;
      } else if (err instanceof Error) {
        msg = err.message;
      }
      setErrorMessage(msg);
    }
  }, [conversationId, roomName, onSessionStarted]);

  // Disconnect and Leave Room (explicitly stops auto-connect from firing again)
  const handleDisconnect = useCallback(() => {
    hasAutoConnectedRef.current = true;
    setTokenData(null);
    setStatus("disconnected");
    onSessionEnded?.();
  }, [onSessionEnded]);

  // Auto connect ONLY ONCE on mount if autoConnect is enabled
  useEffect(() => {
    if (autoConnect && !hasAutoConnectedRef.current && status === "disconnected" && !tokenData) {
      hasAutoConnectedRef.current = true;
      handleConnect();
    }
  }, [autoConnect, handleConnect, status, tokenData]);

  return (
    <div className="w-full flex flex-col items-center justify-center">
      {/* Error Alert */}
      {errorMessage && (
        <div className="mb-4 p-4 bg-rose-500/10 border border-rose-500/30 rounded-2xl text-rose-300 text-xs flex items-center justify-between max-w-md w-full">
          <span>❌ {errorMessage}</span>
          <button
            type="button"
            onClick={handleConnect}
            className="px-2.5 py-1 bg-rose-500/20 hover:bg-rose-500/30 rounded-lg text-rose-200 font-semibold cursor-pointer"
          >
            Thử lại
          </button>
        </div>
      )}

      {/* Main Connection View */}
      {tokenData && status === "connected" ? (
        <LiveKitRoom
          serverUrl={tokenData.server_url}
          token={tokenData.token}
          connect={true}
          audio={true}
          video={false}
          onDisconnected={handleDisconnect}
          onError={(err) => {
            setErrorMessage(`Lỗi WebRTC: ${err.message}`);
            setStatus("error");
          }}
        >
          {/* Native browser audio output from remote tracks */}
          <RoomAudioRenderer />

          <RoomController
            onDisconnect={handleDisconnect}
            onSendMessage={onSendMessage}
            latestUserText={latestUserText}
            latestAssistantText={latestAssistantText}
          />
        </LiveKitRoom>
      ) : (
        /* Standby Welcome / Connecting View (Full Screen Living Orb, No Boxy Card) */
        <div className="flex flex-col items-center justify-center text-center py-6 px-4 max-w-md w-full animate-in fade-in">
          {/* Animated Glowing Orb Standby */}
          <div className="relative flex items-center justify-center my-6">
            <div className="absolute w-60 h-60 rounded-full bg-teal-500/20 blur-3xl animate-pulse pointer-events-none" />
            <div className="relative flex items-center justify-center w-40 h-40 sm:w-48 sm:h-48 rounded-full bg-gradient-to-tr from-teal-500 to-emerald-400 shadow-2xl shadow-teal-500/30">
              {status === "connecting" ? (
                <div className="w-12 h-12 border-3 border-slate-950/30 border-t-slate-950 rounded-full animate-spin" />
              ) : (
                <span className="text-5xl sm:text-6xl select-none">🌴</span>
              )}
            </div>
          </div>

          <h3 className="text-lg font-bold text-slate-100">
            {status === "connecting"
              ? "Đang kết nối LiveKit Voice..."
              : "Trò chuyện trực tiếp cùng TravelWise AI"}
          </h3>
          <p className="text-xs sm:text-sm text-slate-400 mt-2 max-w-sm leading-relaxed">
            {status === "connecting"
              ? "Đang thiết lập kênh âm thanh hai chiều độ trễ siêu thấp..."
              : "Trải nghiệm đàm thoại tự nhiên như gọi điện cho hướng dẫn viên bản địa."}
          </p>

          <button
            type="button"
            onClick={handleConnect}
            disabled={status === "connecting"}
            className="mt-6 px-8 py-3.5 bg-gradient-to-r from-teal-500 via-teal-400 to-emerald-400 hover:brightness-110 text-slate-950 font-bold text-sm sm:text-base rounded-2xl transition-all shadow-xl shadow-teal-500/30 active:scale-95 disabled:opacity-50 cursor-pointer flex items-center gap-2.5"
          >
            {status === "connecting" ? (
              <span>Đang kết nối...</span>
            ) : (
              <>
                <span>⚡ Bắt đầu đàm thoại</span>
              </>
            )}
          </button>
        </div>
      )}
    </div>
  );
}
