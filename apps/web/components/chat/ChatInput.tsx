"use client";

import React, { useState, useRef, useEffect } from "react";

interface ChatInputProps {
  onSendMessage: (message: string) => void;
  isLoading: boolean;
}

export function ChatInput({ onSendMessage, isLoading }: ChatInputProps) {
  const [input, setInput] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Auto resize textarea based on content height
  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
      textareaRef.current.style.height = `${Math.min(
        textareaRef.current.scrollHeight,
        150
      )}px`;
    }
  }, [input]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;
    onSendMessage(input);
    setInput("");
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  return (
    <div className="sticky bottom-0 left-0 right-0 z-20 bg-gradient-to-t from-slate-950 via-slate-950/95 to-transparent pt-4 pb-6 px-4">
      <div className="max-w-3xl mx-auto">
        <form
          onSubmit={handleSubmit}
          className="relative flex items-end gap-2 p-2 rounded-2xl bg-slate-900/90 border border-slate-800 focus-within:border-teal-500/60 focus-within:ring-2 focus-within:ring-teal-500/20 shadow-2xl backdrop-blur-xl transition-all duration-200"
        >
          {/* AI Sparkle Icon inside input */}
          <div className="pl-3 pb-2 text-teal-400">
            <svg
              className={`w-5 h-5 ${isLoading ? "animate-spin text-teal-400" : ""}`}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              {isLoading ? (
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              ) : (
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                />
              )}
            </svg>
          </div>

          {/* Text Area Input */}
          <textarea
            ref={textareaRef}
            rows={1}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Hỏi TravelWise AI về địa điểm, ẩm thực, lịch trình du lịch..."
            disabled={isLoading}
            className="flex-1 bg-transparent text-sm text-slate-100 placeholder-slate-500 resize-none outline-none py-2 px-1 max-h-36 min-h-[40px] leading-relaxed"
          />

          {/* Send Button */}
          <button
            type="submit"
            disabled={!input.trim() || isLoading}
            className={`flex items-center justify-center w-10 h-10 rounded-xl transition-all duration-200 flex-shrink-0 ${
              input.trim() && !isLoading
                ? "bg-gradient-to-r from-teal-500 to-emerald-400 text-slate-950 shadow-md shadow-teal-500/25 hover:scale-105 active:scale-95 cursor-pointer"
                : "bg-slate-800 text-slate-600 cursor-not-allowed"
            }`}
            title="Gửi câu hỏi"
          >
            <svg
              className="w-5 h-5 translate-x-0.5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2.5"
                d="M14 5l7 7m0 0l-7 7m7-7H3"
              />
            </svg>
          </button>
        </form>

        {/* Input Footer Disclaimer */}
        <p className="mt-2 text-center text-[11px] text-slate-500">
          TravelWise AI tra cứu dữ liệu du lịch chuẩn xác để hỗ trợ bạn. Nhấn <kbd className="px-1 py-0.5 text-[10px] bg-slate-900 border border-slate-800 rounded text-slate-400">Enter</kbd> để gửi, <kbd className="px-1 py-0.5 text-[10px] bg-slate-900 border border-slate-800 rounded text-slate-400">Shift + Enter</kbd> xuống dòng.
        </p>
      </div>
    </div>
  );
}
