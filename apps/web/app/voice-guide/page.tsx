"use client";

import React, { useRef, useEffect, useState, useCallback, Suspense } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useChat } from "@/hooks/useChat";
import { useVoiceCompanion } from "@/hooks/useVoiceCompanion";
import { VoiceGuideHeader } from "@/components/voice-guide/VoiceGuideHeader";
import { VoiceMicButton } from "@/components/voice-guide/VoiceMicButton";
import { VoiceMessageBubble } from "@/components/voice-guide/VoiceMessageBubble";
import { TextInputModal } from "@/components/voice-guide/TextInputModal";
import { TripCanvas } from "@/components/canvas/TripCanvas";
import { SuggestedQuestions } from "@/components/chat/SuggestedQuestions";
import { isCreateItineraryCommand } from "@/lib/utils";

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
  // Modal nhập liệu bàn phím dự phòng (tách biệt hoàn toàn với giao diện voice chính)
  const [isTextInputModalOpen, setIsTextInputModalOpen] = useState(false);

  // Tự động mở thanh bên khi có câu lệnh tạo lịch trình
  const handleSendMessage = useCallback(
    async (text: string, mode: "chat" | "voice" = "voice") => {
      if (isCreateItineraryCommand(text)) {
        setIsCanvasOpen(true);
      }
      return sendMessage(text, mode);
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
      // Ngắt lời AI đang nói và lắng nghe người dùng tiếp tục ngay lập tức
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
      {/* Cột chính: Voice AI Guide */}
      <div className="flex flex-col flex-1 h-full min-w-0 overflow-hidden bg-slate-950">
        {/* 1. Header Voice Guide */}
        <VoiceGuideHeader
          onClearHistory={() => {
            stopAudio();
            clearMessages();
            setIsCanvasOpen(false);
          }}
          isCanvasOpen={isCanvasOpen}
          onToggleCanvas={() => setIsCanvasOpen((prev) => !prev)}
        />

        {/* 2. Danh sách tin nhắn đối thoại qua lại */}
        <main className="flex-1 overflow-y-auto custom-scrollbar px-3 sm:px-6 py-4">
          <div className="max-w-3xl mx-auto space-y-4">
            {messages.map((message) => (
              <VoiceMessageBubble
                key={message.id}
                message={message}
                onGenerateProposal={handleGenerateProposal}
              />
            ))}

            {/* Transcript hiển thị thời gian thực khi đang nói */}
            {transcript && (
              <div className="w-full max-w-2xl mx-auto rounded-2xl bg-slate-900/40 border border-teal-500/30 p-3.5 animate-pulse">
                <div className="flex items-center gap-2 mb-1">
                  <span className="w-2 h-2 rounded-full bg-teal-400 animate-ping" />
                  <span className="text-xs text-teal-300 font-medium">Đang nhận diện giọng nói...</span>
                </div>
                <p className="text-sm text-slate-200 italic pl-4">
                  &ldquo;{transcript}&rdquo;
                </p>
              </div>
            )}

            {/* Gợi ý câu hỏi khi mới bắt đầu */}
            {messages.length <= 1 && (
              <div className="pt-2">
                <SuggestedQuestions
                  onSelectQuestion={(q) => {
                    stopAudio();
                    handleSendMessage(q);
                  }}
                />
              </div>
            )}

            <div ref={messagesEndRef} className="h-4" />
          </div>
        </main>

        {/* 3. Khu vực tương tác Voice-First ở đáy màn hình (Hoàn toàn bỏ thanh gõ phím) */}
        <div className="flex-shrink-0 flex flex-col items-center justify-center pt-2 pb-6 px-4 bg-gradient-to-t from-slate-950 via-slate-950/95 to-transparent z-20">
          {/* Nút Micro tròn lớn phát sáng: BẤM ĐỂ NÓI */}
          <VoiceMicButton
            voiceState={voiceState}
            isRecording={isRecording}
            onClick={handleMicClick}
            disabled={isLoading || isPlanning}
          />

          {/* Dòng chữ hướng dẫn trạng thái */}
          <p className="mt-3 text-xs sm:text-sm text-slate-400 font-medium text-center">
            {statusMessage || "Nhấn vào micro để trò chuyện trực tiếp với hướng dẫn viên"}
          </p>

          {/* Nút chuyển sang Chat Box khi không tiện nói */}
          <Link
            href={
              searchParams.get("conversation_id")
                ? `/chat?conversation_id=${searchParams.get("conversation_id")}`
                : "/chat"
            }
            className="mt-2 flex items-center gap-1.5 px-3 py-1 text-xs text-slate-400 hover:text-teal-300 bg-slate-900/60 hover:bg-slate-900 border border-slate-800 rounded-full transition-all cursor-pointer group"
          >
            <span>💬 Không tiện nói?</span>
            <span className="underline underline-offset-2 font-semibold text-teal-400 group-hover:text-teal-300">
              Chuyển sang Chat Box
            </span>
          </Link>
        </div>
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

      {/* 5. Modal nhập liệu bàn phím dự phòng tách biệt hoàn toàn */}
      <TextInputModal
        isOpen={isTextInputModalOpen}
        onClose={() => setIsTextInputModalOpen(false)}
        onSendMessage={(text) => {
          stopAudio();
          handleSendMessage(text);
        }}
        isLoading={isLoading || isPlanning}
      />
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
