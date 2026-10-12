"use client";

import React from "react";

export type VoiceState = "idle" | "listening" | "thinking" | "speaking";

interface VoiceTourGuideBarProps {
  voiceState: VoiceState;
  isRecording: boolean;
  transcript: string;
  autoSpeak: boolean;
  onToggleAutoSpeak: () => void;
  isHandsFree: boolean;
  onToggleHandsFree: () => void;
  onStartListening: () => void;
  onStopListening: () => void;
  onStopSpeaking: () => void;
  statusMessage?: string;
}

export function VoiceTourGuideBar({
  voiceState,
  isRecording,
  transcript,
  autoSpeak,
  onToggleAutoSpeak,
  isHandsFree,
  onToggleHandsFree,
  onStartListening,
  onStopListening,
  onStopSpeaking,
  statusMessage,
}: VoiceTourGuideBarProps) {
  const isListening = voiceState === "listening" || isRecording;
  const isSpeaking = voiceState === "speaking";
  const isThinking = voiceState === "thinking";

  return (
    <div className="relative mx-auto w-full max-w-4xl px-4 pt-3 pb-2 transition-all">
      <div className="relative overflow-hidden rounded-2xl bg-gradient-to-r from-slate-900/95 via-teal-950/40 to-slate-900/95 border border-teal-500/30 p-3 sm:p-4 shadow-xl backdrop-blur-xl">
        {/* Ambient Glow */}
        <div
          className={`absolute -top-12 left-1/2 -translate-x-1/2 w-72 h-32 rounded-full blur-3xl pointer-events-none transition-all duration-700 ${
            isListening
              ? "bg-rose-500/20"
              : isSpeaking
              ? "bg-teal-400/25"
              : isThinking
              ? "bg-amber-400/20"
              : "bg-teal-500/10"
          }`}
        />

        <div className="relative flex flex-col sm:flex-row items-center justify-between gap-3">
          {/* Left: AI Voice Guide Avatar & Status */}
          <div className="flex items-center gap-3 w-full sm:w-auto">
            <div className="relative flex-shrink-0 flex items-center justify-center">
              <div
                className={`w-12 h-12 rounded-2xl flex items-center justify-center transition-all duration-300 shadow-lg ${
                  isListening
                    ? "bg-gradient-to-tr from-rose-500 to-amber-500 scale-110 shadow-rose-500/40 ring-4 ring-rose-500/20"
                    : isSpeaking
                    ? "bg-gradient-to-tr from-teal-400 to-emerald-400 scale-105 shadow-teal-500/40 ring-4 ring-teal-500/20"
                    : isThinking
                    ? "bg-gradient-to-tr from-amber-400 to-orange-500 animate-pulse shadow-amber-500/30"
                    : "bg-gradient-to-tr from-teal-600 to-cyan-600 shadow-teal-900/40"
                }`}
              >
                {isListening ? (
                  <span className="text-xl animate-bounce">🎙️</span>
                ) : isSpeaking ? (
                  <span className="text-xl animate-pulse">🔊</span>
                ) : isThinking ? (
                  <span className="text-xl animate-spin">🧠</span>
                ) : (
                  <span className="text-xl">🌴</span>
                )}
              </div>

              {(isListening || isSpeaking) && (
                <span className="absolute -inset-1 rounded-2xl border-2 border-teal-400/60 animate-ping opacity-50 pointer-events-none" />
              )}
            </div>

            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold uppercase tracking-wider text-teal-300">
                  AI Voice Tour Guide
                </span>
                <span
                  className={`inline-flex items-center px-2 py-0.2 rounded-full text-[10px] font-semibold border ${
                    isListening
                      ? "bg-rose-500/10 text-rose-300 border-rose-500/30 animate-pulse"
                      : isSpeaking
                      ? "bg-emerald-500/10 text-emerald-300 border-emerald-500/30"
                      : isThinking
                      ? "bg-amber-500/10 text-amber-300 border-amber-500/30"
                      : "bg-teal-500/10 text-teal-400 border-teal-500/20"
                  }`}
                >
                  {isListening
                    ? "● Đang lắng nghe..."
                    : isSpeaking
                    ? "● Đang nói câu trả lời"
                    : isThinking
                    ? "● Đang suy nghĩ..."
                    : "● Sẵn sàng hội thoại"}
                </span>
              </div>

              <p className="text-xs text-slate-300 truncate mt-0.5 max-w-md">
                {isListening && transcript ? (
                  <span className="text-rose-200 font-medium">
                    &ldquo;{transcript}&rdquo;
                  </span>
                ) : isSpeaking ? (
                  <span className="text-emerald-300">
                    Đang phát âm thanh giọng đọc hướng dẫn viên...
                  </span>
                ) : isThinking ? (
                  <span className="text-amber-200 italic">
                    AI đang tra cứu địa điểm và tổng hợp câu trả lời...
                  </span>
                ) : (
                  statusMessage || "Trò chuyện bằng giọng nói như đang đồng hành cùng hướng dẫn viên bản địa."
                )}
              </p>
            </div>
          </div>

          {/* Sound Waves */}
          {(isListening || isSpeaking) && (
            <div className="flex items-center gap-1 h-6 px-3 py-1 rounded-xl bg-slate-950/60 border border-slate-800">
              {[40, 75, 55, 90, 60, 85, 45, 95, 70, 50].map((h, i) => (
                <span
                  key={i}
                  className={`w-1 rounded-full transition-all duration-150 ${
                    isListening
                      ? "bg-rose-400 animate-pulse"
                      : "bg-teal-400 animate-bounce"
                  }`}
                  style={{
                    height: `${h}%`,
                    animationDelay: `${i * 70}ms`,
                  }}
                />
              ))}
            </div>
          )}

          {/* Controls */}
          <div className="flex items-center gap-2 w-full sm:w-auto justify-end">
            {isSpeaking && (
              <button
                type="button"
                onClick={() => {
                  onStopSpeaking();
                  onStartListening();
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 border border-rose-500/40 text-xs font-semibold transition-all cursor-pointer"
                title="Dừng phát giọng đọc và lắng nghe ngay"
              >
                <span>⏹ Dừng & nói tiếp</span>
              </button>
            )}

            <button
              type="button"
              onClick={onToggleAutoSpeak}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl border text-xs font-semibold transition-all cursor-pointer ${
                autoSpeak
                  ? "bg-teal-500/20 text-teal-300 border-teal-500/40 shadow-sm"
                  : "bg-slate-800/80 text-slate-400 border-slate-700/80 hover:text-slate-200"
              }`}
              title={autoSpeak ? "Tắt tự động đọc bằng giọng nói" : "Bật tự động đọc bằng giọng nói"}
            >
              <span>{autoSpeak ? "🔊" : "🔇"}</span>
              <span className="hidden md:inline">
                {autoSpeak ? "Tự động đọc: Bật" : "Tự động đọc: Tắt"}
              </span>
            </button>

            <button
              type="button"
              onClick={onToggleHandsFree}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl border text-xs font-semibold transition-all cursor-pointer ${
                isHandsFree
                  ? "bg-emerald-500/20 text-emerald-300 border-emerald-500/40 shadow-sm"
                  : "bg-slate-800/80 text-slate-400 border-slate-700/80 hover:text-slate-200"
              }`}
              title="Chế độ đối thoại 2 chiều rảnh tay liên tục"
            >
              <span>⚡</span>
              <span className="hidden md:inline">Rảnh tay 2 chiều</span>
            </button>

            <button
              type="button"
              onClick={
                isSpeaking
                  ? () => {
                      onStopSpeaking();
                      onStartListening();
                    }
                  : isListening
                  ? onStopListening
                  : onStartListening
              }
              className={`flex items-center gap-2 px-4 py-2 rounded-xl font-bold text-xs shadow-lg transition-all cursor-pointer active:scale-95 ${
                isListening
                  ? "bg-rose-600 hover:bg-rose-500 text-white shadow-rose-900/40 animate-pulse"
                  : isSpeaking
                  ? "bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-emerald-900/40"
                  : "bg-gradient-to-r from-teal-500 via-cyan-400 to-teal-400 hover:brightness-110 text-slate-950 shadow-teal-900/40"
              }`}
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="2.5"
                  d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
                />
              </svg>
              <span>{isListening ? "Dừng nghe" : isSpeaking ? "Nói ngay" : "Nói chuyện"}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
