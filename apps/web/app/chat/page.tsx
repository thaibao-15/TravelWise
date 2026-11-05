"use client";

import React, { useRef, useEffect, useState, useCallback, Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { useChat } from "@/hooks/useChat";
import { useVoiceCompanion } from "@/hooks/useVoiceCompanion";
import { ChatHeader } from "@/components/chat/ChatHeader";
import { ChatMessage } from "@/components/chat/ChatMessage";
import { ChatInput } from "@/components/chat/ChatInput";
import { SuggestedQuestions } from "@/components/chat/SuggestedQuestions";
import { VoiceTourGuideBar } from "@/components/chat/VoiceTourGuideBar";
import { VoiceChatModal } from "@/components/chat/VoiceChatModal";
import { TripCanvas } from "@/components/canvas/TripCanvas";
import { isCreateItineraryCommand } from "@/lib/utils";

function ChatContent() {
  const {
    messages,
    isLoading,
    isPlanning,
    planningContext,
    currentItinerary,
    sendMessage,
    retryMessage,
    clearMessages,
    clearItinerary,
    regenerateItinerary,
    loadConversation,
    generateFromProposal,
    editFromChat,
  } = useChat();

  const searchParams = useSearchParams();
  const initialQuerySent = useRef(false);
  const initialConvLoaded = useRef(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const [isVoiceModalOpen, setIsVoiceModalOpen] = useState(false);
  // Mặc định thanh bên phải (Trip Canvas) KHÔNG hiển thị
  const [isCanvasOpen, setIsCanvasOpen] = useState(false);

  // Tự động mở thanh bên khi có câu lệnh tạo lịch trình
  const handleSendMessage = useCallback(
    async (text: string, mode: "chat" | "voice" = "chat") => {
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

  // Tự động tải lại lịch sử hội thoại nếu có conversation_id trên URL hoặc localStorage (giữ nguyên phòng khi reload)
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
        // Đồng bộ lên URL nếu URL ban đầu chưa có param để người dùng reload vẫn giữ nguyên phòng
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

  // Auto-send query from URL query parameter (e.g. /chat?q=...)
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
  }, [messages, isLoading, isPlanning, voiceState]);

  return (
    <div className="flex h-screen max-h-screen bg-slate-950 text-slate-100 overflow-hidden font-sans">
      {/* Cột chính: Chat Conversation + Voice Bar */}
      <div className="flex flex-col flex-1 h-full min-w-0 overflow-hidden bg-slate-950">
        {/* Sticky Header */}
        <ChatHeader
          onClearHistory={() => {
            stopAudio();
            clearMessages();
            setIsCanvasOpen(false);
          }}
          messageCount={messages.length}
          onOpenVoiceMode={() => setIsVoiceModalOpen(true)}
          onToggleCanvas={() => setIsCanvasOpen((prev) => !prev)}
          isCanvasOpen={isCanvasOpen}
        />

        {/* Thanh điều khiển Voice Tour Guide thời gian thực (Tính năng chính) */}
        <VoiceTourGuideBar
          voiceState={voiceState}
          isRecording={isRecording}
          transcript={transcript}
          autoSpeak={autoSpeak}
          onToggleAutoSpeak={toggleAutoSpeak}
          isHandsFree={isHandsFree}
          onToggleHandsFree={toggleHandsFree}
          onStartListening={startListening}
          onStopListening={stopListening}
          onStopSpeaking={stopAudio}
          statusMessage={statusMessage}
          onOpenLiveKitModal={() => setIsVoiceModalOpen(true)}
        />

        {/* Khu vực danh sách tin nhắn hội thoại */}
        <main className="flex-1 overflow-y-auto custom-scrollbar px-2 sm:px-4 py-2">
          <div className="max-w-4xl mx-auto space-y-2">
            {messages.map((message, idx) => (
              <ChatMessage
                key={message.id}
                message={message}
                isLatest={idx === messages.length - 1}
                planningContext={planningContext}
                hasItinerary={Boolean(currentItinerary)}
                onRetry={retryMessage}
                onGenerateProposal={handleGenerateProposal}
                onMoreChat={() => {
                  startListening();
                }}
                onEditPrompt={editFromChat}
                isPlanning={isPlanning}
              />
            ))}

            {/* Gợi ý câu hỏi khi mới bắt đầu */}
            {messages.length <= 1 && (
              <div className="pt-2">
                <SuggestedQuestions onSelectQuestion={handleSendMessage} />
              </div>
            )}

            {/* Điểm neo tự động cuộn xuống đáy */}
            <div ref={messagesEndRef} className="h-4" />
          </div>
        </main>

        {/* Thanh nhập liệu tích hợp giọng nói */}
        <ChatInput
          onSendMessage={handleSendMessage}
          isLoading={isLoading || isPlanning}
          onOpenVoiceMode={() => {
            if (isRecording) {
              stopListening();
            } else {
              startListening();
            }
          }}
        />
      </div>

      {/* Cột bên phải: Trip Canvas (Hiển thị lịch trình trực tiếp ở thanh bên phải) */}
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

      {/* Modal gọi thoại 2 chiều toàn màn hình (Tùy chọn phóng to) */}
      <VoiceChatModal
        isOpen={isVoiceModalOpen}
        onClose={() => setIsVoiceModalOpen(false)}
        onSendMessage={handleSendMessage}
        isLoadingChat={isLoading || isPlanning}
        conversationId={
          searchParams.get("conversation_id")
            ? parseInt(searchParams.get("conversation_id")!, 10)
            : null
        }
      />
    </div>
  );
}

export default function ChatPage() {
  return (
    <Suspense
      fallback={
        <div className="h-screen bg-slate-950 text-slate-400 flex items-center justify-center font-sans">
          <div className="flex items-center gap-3">
            <span className="w-3 h-3 rounded-full bg-teal-400 animate-ping"></span>
            <span>Đang tải TravelWise AI Voice Tour Guide...</span>
          </div>
        </div>
      }
    >
      <ChatContent />
    </Suspense>
  );
}
