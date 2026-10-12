"use client";

import React from "react";
import { VoiceState } from "@/hooks/useVoiceCompanion";

interface VoiceMicButtonProps {
  voiceState: VoiceState;
  isRecording: boolean;
  onClick: () => void;
  disabled?: boolean;
}

export function VoiceMicButton({
  voiceState,
  isRecording,
  onClick,
  disabled = false,
}: VoiceMicButtonProps) {
  const isListening = voiceState === "listening" || isRecording;
  const isSpeaking = voiceState === "speaking";
  const isThinking = voiceState === "thinking";

  let label = "BẤM ĐỂ NÓI";
  if (isListening) label = "ĐANG NGHE...";
  else if (isThinking) label = "ĐANG XỬ LÝ...";
  else if (isSpeaking) label = "DỪNG LẠI";

  return (
    <div className="relative flex flex-col items-center justify-center">
      {/* Concentric Pulsing Waves when listening */}
      {isListening && (
        <>
          <span className="absolute w-28 h-28 sm:w-32 sm:h-32 rounded-full bg-teal-400/20 animate-ping pointer-events-none" />
          <span className="absolute w-36 h-36 sm:w-40 sm:h-40 rounded-full border-2 border-teal-400/40 animate-pulse pointer-events-none" />
        </>
      )}

      {/* Speaking Soundwave Glow */}
      {isSpeaking && (
        <span className="absolute w-28 h-28 sm:w-32 sm:h-32 rounded-full bg-emerald-400/25 animate-pulse pointer-events-none" />
      )}

      {/* The Big Center Circular Button matching Screenshot 2 */}
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        className={`relative z-10 w-24 h-24 sm:w-28 sm:h-28 rounded-full flex flex-col items-center justify-center text-slate-950 font-black transition-all duration-300 shadow-2xl active:scale-95 cursor-pointer ${
          isListening
            ? "bg-gradient-to-tr from-rose-500 via-amber-400 to-rose-400 text-slate-950 shadow-rose-500/50 scale-105"
            : isSpeaking
            ? "bg-gradient-to-tr from-teal-300 via-emerald-400 to-teal-400 text-slate-950 shadow-teal-400/60 ring-4 ring-teal-400/30"
            : isThinking
            ? "bg-gradient-to-tr from-amber-400 to-cyan-400 text-slate-950 animate-pulse shadow-amber-400/50"
            : "bg-gradient-to-tr from-[#00f5a0] to-[#00d9f5] hover:scale-105 shadow-[0_0_35px_rgba(0,245,160,0.45)] ring-4 ring-teal-400/20"
        } ${disabled ? "opacity-50 cursor-not-allowed" : ""}`}
        title={
          isSpeaking
            ? "Dừng giọng đọc AI"
            : isListening
            ? "Dừng nghe và gửi câu hỏi"
            : "Bấm để bắt đầu nói chuyện"
        }
      >
        {isThinking ? (
          <svg className="w-8 h-8 sm:w-9 sm:h-9 animate-spin text-slate-950" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.5" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        ) : isSpeaking ? (
          <span className="text-2xl sm:text-3xl animate-pulse">⏹</span>
        ) : (
          <svg
            className={`w-8 h-8 sm:w-9 sm:h-9 text-slate-950 ${isListening ? "animate-bounce" : ""}`}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2.5"
              d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
            />
          </svg>
        )}

        <span className="text-[10px] sm:text-[11px] font-extrabold tracking-wider uppercase mt-1 leading-none text-slate-950">
          {label}
        </span>
      </button>
    </div>
  );
}
