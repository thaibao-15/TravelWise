"use client";

import React, { useState, useRef, useEffect, useCallback } from "react";
import { useSpeechToText } from "@/hooks/useSpeechToText";

interface ChatInputProps {
  onSendMessage: (message: string) => void;
  isLoading: boolean;
}

export function ChatInput({ onSendMessage, isLoading }: ChatInputProps) {
  const [input, setInput] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const baseTextRef = useRef("");

  // Real-time transcript handler
  const handleTranscript = useCallback((text: string, isFinal: boolean) => {
    const prefix = baseTextRef.current ? `${baseTextRef.current} ` : "";
    const updated = `${prefix}${text}`;
    setInput(updated);

    if (isFinal) {
      baseTextRef.current = updated;
    }
  }, []);

  const {
    isRecording,
    isConnecting,
    isProcessing,
    error: sttError,
    clearError: clearSttError,
    startRecording,
    stopRecording,
  } = useSpeechToText({
    onTranscript: handleTranscript,
  });

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

    if (isRecording || isConnecting) {
      stopRecording();
    }

    onSendMessage(input);
    setInput("");
    baseTextRef.current = "";
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

  const toggleRecording = () => {
    if (isRecording || isConnecting) {
      stopRecording();
    } else {
      baseTextRef.current = input.trim();
      startRecording();
    }
  };

  return (
    <div className="sticky bottom-0 left-0 right-0 z-20 bg-gradient-to-t from-slate-950 via-slate-950/95 to-transparent pt-4 pb-6 px-4">
      <div className="max-w-3xl mx-auto">
        {/* Error Notification Alert */}
        {sttError && (
          <div className="flex items-start justify-between gap-2 px-3 py-2 mb-2 rounded-xl bg-amber-950/60 border border-amber-500/40 text-xs text-amber-200 backdrop-blur-md shadow-lg transition-all animate-in fade-in">
            <div className="flex items-start gap-2">
              <span className="text-amber-400 flex-shrink-0 mt-0.5">⚠️</span>
              <span>{sttError}</span>
            </div>
            <button
              type="button"
              onClick={clearSttError}
              className="text-amber-400 hover:text-amber-200 flex-shrink-0 ml-1 p-0.5 rounded cursor-pointer"
              title="Đóng thông báo"
            >
              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        )}

        {/* Real-time Recording Status Banner */}
        {isRecording && (
          <div className="flex items-center justify-between px-3 py-1.5 mb-2 rounded-xl bg-red-950/50 border border-red-500/30 text-xs text-red-200 backdrop-blur-md shadow-lg animate-in fade-in">
            <div className="flex items-center gap-2">
              <span className="relative flex h-2.5 w-2.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-red-500"></span>
              </span>
              <span className="font-medium text-slate-100">
                🔴 Đang nghe... Hãy nói câu hỏi của bạn (transcript hiển thị trực tiếp vào ô bên dưới)
              </span>
            </div>
            <button
              type="button"
              onClick={stopRecording}
              className="flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-lg bg-red-500/30 hover:bg-red-500/50 text-red-100 transition-colors cursor-pointer"
              title="Dừng ghi âm"
            >
              <span>⏹ Dừng</span>
            </button>
          </div>
        )}

        {/* Processing Status Banner */}
        {isProcessing && !isRecording && (
          <div className="flex items-center gap-2 px-3 py-1.5 mb-2 rounded-xl bg-teal-950/50 border border-teal-500/30 text-xs text-teal-200 backdrop-blur-md shadow-lg animate-in fade-in">
            <span className="w-2.5 h-2.5 rounded-full bg-teal-400 animate-ping"></span>
            <span className="font-medium text-slate-100">
              ⏳ Đang chuyển giọng nói thành văn bản qua Blaze AI...
            </span>
          </div>
        )}

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
            onChange={(e) => {
              setInput(e.target.value);
              baseTextRef.current = e.target.value;
            }}
            onKeyDown={handleKeyDown}
            placeholder={
              isRecording
                ? "Đang ghi âm giọng nói..."
                : isProcessing
                ? "Đang nhận diện giọng nói..."
                : "Hỏi TravelWise AI về địa điểm, ẩm thực, lịch trình du lịch..."
            }
            disabled={isLoading}
            className="flex-1 bg-transparent text-sm text-slate-100 placeholder-slate-500 resize-none outline-none py-2 px-1 max-h-36 min-h-[40px] leading-relaxed"
          />

          {/* Microphone STT Button */}
          {isRecording ? (
            /* Active recording state: ⏹ Dừng ghi âm */
            <button
              type="button"
              onClick={toggleRecording}
              className="flex items-center justify-center w-10 h-10 rounded-xl bg-red-500/20 text-red-400 border border-red-500/50 shadow-md shadow-red-500/20 hover:bg-red-500/30 active:scale-95 cursor-pointer flex-shrink-0 transition-all duration-200"
              title="Dừng ghi âm"
            >
              <span className="w-3.5 h-3.5 bg-red-400 rounded-sm"></span>
            </button>
          ) : isConnecting || isProcessing ? (
            /* Connecting or processing state */
            <button
              type="button"
              disabled
              className="flex items-center justify-center w-10 h-10 rounded-xl bg-slate-800 text-teal-400 flex-shrink-0 cursor-wait"
              title={isConnecting ? "Đang kết nối microphone..." : "Đang xử lý giọng nói..."}
            >
              <svg className="w-5 h-5 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
            </button>
          ) : (
            /* Idle state: 🎤 Chưa ghi âm */
            <button
              type="button"
              onClick={toggleRecording}
              disabled={isLoading}
              className={`flex items-center justify-center w-10 h-10 rounded-xl transition-all duration-200 flex-shrink-0 ${
                isLoading
                  ? "text-slate-600 bg-slate-800/40 cursor-not-allowed"
                  : "text-slate-400 hover:text-teal-300 hover:bg-slate-800/80 active:scale-95 cursor-pointer"
              }`}
              title="Nhập bằng giọng nói (Microphone)"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2"
                  d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
                />
              </svg>
            </button>
          )}

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
