"use client";

import React, { useRef, useEffect, Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { useChat } from "@/hooks/useChat";
import { ChatHeader } from "@/components/chat/ChatHeader";
import { ChatMessage } from "@/components/chat/ChatMessage";
import { ChatInput } from "@/components/chat/ChatInput";
import { SuggestedQuestions } from "@/components/chat/SuggestedQuestions";

function ChatContent() {
  const { messages, isLoading, sendMessage, retryMessage, clearMessages } =
    useChat();
  const searchParams = useSearchParams();
  const initialQuerySent = useRef(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-send query from URL query parameter (e.g. /chat?q=...)
  useEffect(() => {
    const q = searchParams.get("q");
    if (q && !initialQuerySent.current) {
      initialQuerySent.current = true;
      sendMessage(q);
    }
  }, [searchParams, sendMessage]);

  // Auto scroll to bottom when messages update
  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isLoading]);

  return (
    <div className="flex flex-col h-screen max-h-screen bg-slate-950 text-slate-100 overflow-hidden font-sans">
      {/* Sticky Header */}
      <ChatHeader
        onClearHistory={clearMessages}
        messageCount={messages.length}
      />

      {/* Main Chat Conversation Area */}
      <main className="flex-1 overflow-y-auto custom-scrollbar px-2 py-4">
        <div className="max-w-4xl mx-auto">
          {/* Messages list */}
          {messages.map((message) => (
            <ChatMessage
              key={message.id}
              message={message}
              onRetry={retryMessage}
            />
          ))}

          {/* Show Suggested Questions if only welcome message is present */}
          {messages.length <= 1 && (
            <SuggestedQuestions onSelectQuestion={sendMessage} />
          )}

          {/* Bottom scroll anchor */}
          <div ref={messagesEndRef} className="h-4" />
        </div>
      </main>

      {/* Sticky Chat Input Bar */}
      <ChatInput onSendMessage={sendMessage} isLoading={isLoading} />
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
            <span>Đang tải TravelWise AI...</span>
          </div>
        </div>
      }
    >
      <ChatContent />
    </Suspense>
  );
}
