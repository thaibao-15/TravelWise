"use client";

import React, { useRef, useEffect, useState, useCallback, Suspense } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useChat } from "@/hooks/useChat";
import { useVoiceCompanion } from "@/hooks/useVoiceCompanion";
import { VoiceGuideHeader } from "@/components/voice-guide/VoiceGuideHeader";
import { VoiceMicButton } from "@/components/voice-guide/VoiceMicButton";
import { VoiceMessageBubble } from "@/components/voice-guide/VoiceMessageBubble";
import { TripCanvas } from "@/components/canvas/TripCanvas";
import { LiveKitVoicePanel } from "@/components/livekit/LiveKitVoicePanel";
import { isCreateItineraryCommand } from "@/lib/utils";

const QUICK_VOICE_SUGGESTIONS = [
  {
    icon: "🏝️",
    title: "Lên lịch trình du lịch",
    query: "Lên lịch trình 3 ngày 2 đêm tại Đà Nẵng và Hội An cho 2 người",
    tag: "Lịch trình",
  },
  {
    icon: "🍜",
    title: "Đặc sản & Quán ngon",
    query: "Những món ăn đặc sản ngon nức tiếng tại Đà Nẵng kèm địa chỉ",
    tag: "Ẩm thực",
  },
  {
    icon: "🚗",
    title: "Di chuyển & Kinh nghiệm",
    query: "Kinh nghiệm đi Bà Nà Hills tự túc tiết kiệm nhất",
    tag: "Kinh nghiệm",
  },
  {
    icon: "🌤️",
    title: "Thời tiết & Mùa đẹp",
    query: "Thời điểm nào trong năm đi du lịch Đà Nẵng đẹp và ít mưa nhất?",
    tag: "Thời tiết",
  },
];

function VoiceGuideContent() {
  const {
    messages,
    isLoading,
    isPlanning,
    planningContext,
    currentItinerary,
    sendMessage,
    clearMessages,
    clearItinerary,
    regenerateItinerary,
    loadConversation,
    generateFromProposal,
  } = useChat();

  const searchParams = useSearchParams();
  const initialQuerySent = useRef(false);
  const initialConvLoaded = useRef(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Mặc định thanh bên phải (Trip Canvas) KHÔNG hiển thị
  const [isCanvasOpen, setIsCanvasOpen] = useState(false);
  // Chế độ Voice Engine: LiveKit WebRTC (Khuyên dùng) hoặc Voice WebSocket cũ (Option A)
  const [voiceEngineMode, setVoiceEngineMode] = useState<"livekit" | "legacy">("livekit");

  // Tự động mở thanh bên khi có câu lệnh tạo lịch trình
  const handleSendMessage = useCallback(
    async (
      text: string,
      mode: "chat" | "voice" = "voice",
      onSentence?: (sentence: string) => void
    ) => {
      if (isCreateItineraryCommand(text)) {
        setIsCanvasOpen(true);
      }
      return sendMessage(text, mode, onSentence);
    },
    [sendMessage]
  );

  const handleGenerateProposal = useCallback(
    async (proposalOrPrompt?: any, customPrompt?: string) => {
      setIsCanvasOpen(true);
      return generateFromProposal(proposalOrPrompt, customPrompt);
    },
    [generateFromProposal]
  );

  const handleRegenerateItinerary = useCallback(
    async (promptText?: string) => {
      setIsCanvasOpen(true);
      return regenerateItinerary(promptText);
    },
    [regenerateItinerary]
  );

  // Tự động mở thanh bên khi hệ thống bắt đầu tạo / lập lịch trình
  useEffect(() => {
    if (isPlanning) {
      setIsCanvasOpen(true);
    }
  }, [isPlanning]);

  // Hook điều khiển Voice Tour Guide thời gian thực
  const {
    voiceState,
    isRecording,
    transcript,
    autoSpeak,
    isHandsFree,
    statusMessage,
    startListening,
    stopListening,
    stopAudio,
    toggleAutoSpeak,
    toggleHandsFree,
  } = useVoiceCompanion({
    onSendMessage: handleSendMessage,
    isLoadingChat: isLoading || isPlanning,
  });

  // Tự động tải lại lịch sử hội thoại nếu có conversation_id trên URL hoặc localStorage
  useEffect(() => {
    if (initialConvLoaded.current) return;

    let targetConvId: string | null = searchParams.get("conversation_id");
    if (!targetConvId && typeof window !== "undefined") {
      targetConvId = localStorage.getItem("travelwise_conversation_id");
    }

    if (targetConvId) {
      initialConvLoaded.current = true;
      const numId = parseInt(targetConvId, 10);
      if (!isNaN(numId)) {
        loadConversation(numId);
        if (typeof window !== "undefined") {
          const currentUrl = new URL(window.location.href);
          if (currentUrl.searchParams.get("conversation_id") !== String(numId)) {
            currentUrl.searchParams.set("conversation_id", String(numId));
            window.history.replaceState(null, "", currentUrl.toString());
          }
        }
      }
    }
  }, [searchParams, loadConversation]);

  // Auto-send query from URL query parameter (e.g. /voice-guide?q=...)
  useEffect(() => {
    const q = searchParams.get("q");
    if (q && !initialQuerySent.current) {
      initialQuerySent.current = true;
      handleSendMessage(q);
    }
  }, [searchParams, handleSendMessage]);

  // Auto scroll to bottom when messages update
  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isLoading, isPlanning, voiceState, transcript]);

  // Xử lý khi nhấn nút Micro tròn lớn ở giữa
  const handleMicClick = () => {
    if (voiceState === "speaking") {
      stopAudio();
      startListening();
    } else if (voiceState === "listening" || isRecording) {
      stopListening();
    } else {
      startListening();
    }
  };


  return (
    <div className="flex h-screen max-h-screen bg-slate-950 text-slate-100 overflow-hidden font-sans">
      {/* Background Ambient Glows */}
      <div className="fixed top-1/4 left-1/4 w-[400px] h-[400px] bg-teal-500/5 rounded-full blur-3xl pointer-events-none" />
      <div className="fixed bottom-1/4 right-1/4 w-[450px] h-[450px] bg-cyan-500/5 rounded-full blur-3xl pointer-events-none" />

      {/* Cột chính: Voice AI Guide */}
      <div className="flex flex-col flex-1 h-full min-w-0 overflow-hidden bg-slate-950/60 backdrop-blur-sm relative z-10">
        {/* 1. Header Voice Guide */}
        <VoiceGuideHeader
          onClearHistory={() => {
            stopAudio();
            clearMessages();
            setIsCanvasOpen(false);
          }}
          isCanvasOpen={isCanvasOpen}
          onToggleCanvas={() => setIsCanvasOpen((prev) => !prev)}
          autoSpeak={autoSpeak}
          onToggleAutoSpeak={toggleAutoSpeak}
        />

        {/* Sub-header Engine Mode Selector (Option A) */}
        <div className="flex items-center justify-center py-2.5 px-4 relative z-20">
          <div className="inline-flex items-center p-1 rounded-2xl bg-slate-900/90 border border-slate-800 shadow-xl backdrop-blur-xl">
            <button
              type="button"
              onClick={() => {
                stopAudio();
                stopListening();
                setVoiceEngineMode("livekit");
              }}
              className={`flex items-center gap-2 px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all cursor-pointer ${
                voiceEngineMode === "livekit"
                  ? "bg-gradient-to-r from-teal-500 to-emerald-500 text-slate-950 font-bold shadow-md shadow-teal-500/25"
                  : "text-slate-400 hover:text-slate-200"
              }`}
              title="LiveKit WebRTC: Đàm thoại 2 chiều liên tục, tự động ngắt lời khi bạn nói"
            >
              <span>⚡ LiveKit Realtime</span>
              <span className="px-1.5 py-0.2 rounded-full bg-slate-950/20 text-[9px] uppercase font-bold tracking-wider">
                Khuyên dùng
              </span>
            </button>

            <button
              type="button"
              onClick={() => setVoiceEngineMode("legacy")}
              className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all cursor-pointer ${
                voiceEngineMode === "legacy"
                  ? "bg-slate-800 text-slate-100 shadow-sm"
                  : "text-slate-400 hover:text-slate-200"
              }`}
              title="Chế độ Voice Tour Guide cũ qua WebSocket / Web Speech API"
            >
              <span>🎙️ Voice WebSocket Cũ</span>
            </button>
          </div>
        </div>

        {/* Dynamic Mode Rendering */}
        {voiceEngineMode === "livekit" ? (
          <main className="flex-1 overflow-y-auto custom-scrollbar flex flex-col items-center px-4 py-4 relative z-10">
            <div className="w-full max-w-xl my-auto flex flex-col items-center">
              <LiveKitVoicePanel
                conversationId={
                  searchParams.get("conversation_id")
                    ? parseInt(searchParams.get("conversation_id")!, 10)
                    : null
                }
                autoConnect={true}
                latestUserText={messages.slice().reverse().find((m) => m.role === "user")?.content}
                latestAssistantText={messages.slice().reverse().find((m) => m.role === "assistant")?.content}
                onSendMessage={async (text) => {
                  return handleSendMessage(text, "voice");
                }}
              />
            </div>

            {/* Chuyển sang Chat Box */}
            <div className="pt-2 pb-4">
              <Link
                href={
                  searchParams.get("conversation_id")
                    ? `/chat?conversation_id=${searchParams.get("conversation_id")}`
                    : "/chat"
                }
                className="flex items-center gap-1.5 px-3.5 py-1.5 text-xs text-slate-400 hover:text-teal-300 transition-all cursor-pointer group rounded-xl hover:bg-slate-900/60 border border-transparent hover:border-slate-800"
              >
                <span>💬 Muốn chat văn bản truyền thống?</span>
                <span className="underline underline-offset-2 font-semibold text-teal-400 group-hover:text-teal-300">
                  Chuyển sang Chat Box
                </span>
              </Link>
            </div>
          </main>
        ) : (
          <>
            {/* 2. Danh sách tin nhắn đối thoại qua lại (Legacy Mode) */}
            <main className="flex-1 overflow-y-auto custom-scrollbar px-3 sm:px-6 py-4">
              <div className="max-w-3xl mx-auto space-y-4">
                {/* Danh sách tin nhắn */}
                {messages.map((message) => (
                  <VoiceMessageBubble
                    key={message.id}
                    message={message}
                    onGenerateProposal={handleGenerateProposal}
                  />
                ))}

                {/* 4 Quick Voice Cards khi cuộc trò chuyện mới bắt đầu */}
                {messages.length <= 1 && (
                  <div className="pt-3 pb-1 animate-in fade-in">
                    <div className="flex items-center gap-2 mb-2 px-1">
                      <span className="text-xs font-semibold text-teal-400">💡 Gợi ý câu hỏi nhanh:</span>
                      <span className="text-[11px] text-slate-500">(Bấm vào hoặc nói trực tiếp)</span>
                    </div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 text-left">
                      {QUICK_VOICE_SUGGESTIONS.map((item, idx) => (
                        <button
                          key={idx}
                          type="button"
                          onClick={() => {
                            stopAudio();
                            handleSendMessage(item.query);
                          }}
                          className="p-3 rounded-2xl bg-slate-900/60 hover:bg-slate-800/80 border border-slate-800/80 hover:border-teal-500/40 shadow-sm transition-all text-left cursor-pointer group flex items-start gap-3 active:scale-[0.98]"
                        >
                          <span className="text-xl flex-shrink-0 mt-0.5">{item.icon}</span>
                          <div className="min-w-0">
                            <span className="text-[10px] font-bold text-teal-400 uppercase tracking-wider block mb-0.5">
                              {item.tag}
                            </span>
                            <p className="text-xs font-medium text-slate-200 group-hover:text-teal-200 line-clamp-2 leading-snug">
                              {item.query}
                            </p>
                          </div>
                        </button>
                      ))}
                    </div>
                  </div>
                )}

                {/* Transcript hiển thị thời gian thực khi đang nói */}
                {transcript && (
                  <div className="w-full max-w-2xl mx-auto rounded-2xl bg-gradient-to-r from-slate-900/90 to-teal-950/30 border border-teal-400/40 p-4 shadow-xl shadow-teal-950/30 backdrop-blur-md animate-pulse">
                    <div className="flex items-center gap-2 mb-1.5">
                      <span className="relative flex h-2.5 w-2.5">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-teal-400 opacity-75" />
                        <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-teal-400" />
                      </span>
                      <span className="text-xs text-teal-300 font-bold uppercase tracking-wider">
                        Đang nhận diện giọng nói của bạn...
                      </span>
                    </div>
                    <p className="text-sm text-slate-100 font-medium pl-4 italic leading-relaxed">
                      &ldquo;{transcript}&rdquo;
                    </p>
                  </div>
                )}

                <div ref={messagesEndRef} className="h-4" />
              </div>
            </main>

            {/* 3. Khu vực tương tác Voice-First ở đáy màn hình (Legacy Mode) */}
            <div className="flex-shrink-0 flex flex-col items-center justify-center pt-2 pb-6 px-4 bg-gradient-to-t from-slate-950 via-slate-950/95 to-transparent z-20">
              {/* 3-State Visual Indicator Pipeline */}
              <div className="flex items-center justify-center gap-1.5 sm:gap-2 mb-3 select-none">
                <div
                  className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all duration-300 ${
                    voiceState === "listening" || isRecording
                      ? "bg-rose-500/20 text-rose-300 border border-rose-500/50 shadow-lg shadow-rose-500/20 scale-105"
                      : "bg-slate-900/50 text-slate-500 border border-slate-800/80"
                  }`}
                >
                  <span className={voiceState === "listening" || isRecording ? "animate-bounce text-sm" : "opacity-50"}>🎙️</span>
                  <span>Đang nghe</span>
                </div>

                <span className="text-slate-600 text-xs">→</span>

                <div
                  className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all duration-300 ${
                    voiceState === "thinking"
                      ? "bg-amber-500/20 text-amber-300 border border-amber-500/50 shadow-lg shadow-amber-500/20 scale-105"
                      : "bg-slate-900/50 text-slate-500 border border-slate-800/80"
                  }`}
                >
                  <span className={voiceState === "thinking" ? "animate-spin text-sm" : "opacity-50"}>🧠</span>
                  <span>Đang phân tích</span>
                </div>

                <span className="text-slate-600 text-xs">→</span>

                <div
                  className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all duration-300 ${
                    voiceState === "speaking"
                      ? "bg-emerald-500/20 text-emerald-300 border border-emerald-500/50 shadow-lg shadow-emerald-500/20 scale-105"
                      : "bg-slate-900/50 text-slate-500 border border-slate-800/80"
                  }`}
                >
                  <span className={voiceState === "speaking" ? "animate-pulse text-sm" : "opacity-50"}>🔊</span>
                  <span>Đang trả lời</span>
                </div>
              </div>

              {/* Nút Micro tròn lớn phát sáng: BẤM ĐỂ NÓI */}
              <VoiceMicButton
                voiceState={voiceState}
                isRecording={isRecording}
                onClick={handleMicClick}
                disabled={isLoading || isPlanning}
              />

              {/* Dòng chữ hướng dẫn trạng thái đàm thoại */}
              <div className="mt-3.5 flex items-center gap-2">
                <span
                  className={`w-2 h-2 rounded-full ${
                    voiceState === "speaking"
                      ? "bg-emerald-400 animate-ping"
                      : voiceState === "listening"
                      ? "bg-rose-400 animate-ping"
                      : voiceState === "thinking"
                      ? "bg-amber-400 animate-spin"
                      : "bg-teal-400"
                  }`}
                />
                <p className="text-xs sm:text-sm text-slate-300 font-medium text-center">
                  {statusMessage || "Nhấn vào micro để trò chuyện trực tiếp"}
                </p>
              </div>

              {/* Nút chuyển sang Chat Box văn bản truyền thống */}
              <Link
                href={
                  searchParams.get("conversation_id")
                    ? `/chat?conversation_id=${searchParams.get("conversation_id")}`
                    : "/chat"
                }
                className="mt-2.5 flex items-center gap-1.5 px-3 py-1 text-xs text-slate-400 hover:text-teal-300 transition-all cursor-pointer group"
              >
                <span>💬 Muốn chat văn bản truyền thống?</span>
                <span className="underline underline-offset-2 font-semibold text-teal-400 group-hover:text-teal-300">
                  Chuyển sang Chat Box
                </span>
              </Link>
            </div>
          </>
        )}
      </div>

      {/* 4. Cột bên phải: Trip Canvas (Hiển thị lịch trình khi bấm Kế hoạch hoặc có lệnh) */}
      {isCanvasOpen && (
        <div className="hidden lg:flex h-full">
          <TripCanvas
            planningContext={planningContext}
            itinerary={currentItinerary}
            isPlanning={isPlanning}
            onGenerateItinerary={() => handleGenerateProposal()}
            onClearItinerary={clearItinerary}
            onRegenerateItinerary={() => handleRegenerateItinerary()}
            onSelectPrompt={handleSendMessage}
            onClose={() => setIsCanvasOpen(false)}
          />
        </div>
      )}

      {/* Drawer Trip Canvas cho Mobile / Tablet */}
      {isCanvasOpen && (
        <div className="fixed inset-0 z-50 flex lg:hidden bg-black/60 backdrop-blur-sm animate-in fade-in">
          <div className="flex-1" onClick={() => setIsCanvasOpen(false)} />
          <div className="w-[420px] sm:w-[460px] max-w-[95vw] h-full shadow-2xl">
            <TripCanvas
              planningContext={planningContext}
              itinerary={currentItinerary}
              isPlanning={isPlanning}
              onGenerateItinerary={() => {
                handleGenerateProposal();
                setIsCanvasOpen(false);
              }}
              onClearItinerary={clearItinerary}
              onRegenerateItinerary={() => {
                handleRegenerateItinerary();
                setIsCanvasOpen(false);
              }}
              onSelectPrompt={(prompt) => {
                handleSendMessage(prompt);
                setIsCanvasOpen(false);
              }}
              onClose={() => setIsCanvasOpen(false)}
            />
          </div>
        </div>
      )}
    </div>
  );
}

export default function VoiceGuidePage() {
  return (
    <Suspense
      fallback={
        <div className="h-screen bg-slate-950 text-slate-400 flex items-center justify-center font-sans">
          <div className="flex items-center gap-3">
            <span className="w-3 h-3 rounded-full bg-teal-400 animate-ping"></span>
            <span>Đang tải TravelWise Voice Guide...</span>
          </div>
        </div>
      }
    >
      <VoiceGuideContent />
    </Suspense>
  );
}
