"use client";

import React, { useState, useRef } from "react";
import { ChatMessage, ItineraryProposalData } from "@/types/chat";
import { ttsService } from "@/services/tts.service";

interface VoiceMessageBubbleProps {
  message: ChatMessage;
  onGenerateProposal?: (proposal?: ItineraryProposalData) => void;
}

export function VoiceMessageBubble({
  message,
  onGenerateProposal,
}: VoiceMessageBubbleProps) {
  const isUser = message.role === "user";
  const [isPlaying, setIsPlaying] = useState(false);
  const [copied, setCopied] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(message.content);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {}
  };

  const handleReplayTTS = async () => {
    if (isPlaying) {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
      setIsPlaying(false);
      return;
    }

    try {
      setIsPlaying(true);
      const cleanContent = message.content.replace(/[*#_`]/g, " ").trim();
      const audioUrl = await ttsService.synthesize(cleanContent);
      const audio = new Audio(audioUrl);
      audioRef.current = audio;
      audio.onended = () => {
        setIsPlaying(false);
        audioRef.current = null;
      };
      audio.onerror = () => {
        setIsPlaying(false);
        audioRef.current = null;
      };
      await audio.play();
    } catch {
      setIsPlaying(false);
    }
  };

  if (isUser) {
    return (
      <div className="w-full max-w-2xl mx-auto flex justify-end">
        <div className="relative max-w-[85%] sm:max-w-[78%] rounded-2xl rounded-tr-sm bg-gradient-to-br from-slate-900/90 to-slate-900/60 border border-teal-500/30 p-4 shadow-lg shadow-teal-950/20 backdrop-blur-md transition-all">
          <div className="flex items-center justify-between gap-3 mb-1.5 pb-1 border-b border-slate-800/60">
            <div className="flex items-center gap-1.5 text-teal-300 text-xs font-semibold">
              <span className="w-2 h-2 rounded-full bg-teal-400"></span>
              <span>Bạn</span>
            </div>
            <span className="text-[10px] text-slate-400 flex items-center gap-1">
              <span>🎙️ Voice</span>
            </span>
          </div>

          <p className="text-sm text-slate-100 font-medium leading-relaxed whitespace-pre-wrap">
            {message.content}
          </p>
        </div>
      </div>
    );
  }

  // Assistant Message: TravelWise Guide
  return (
    <div className="w-full max-w-2xl mx-auto">
      <div className="rounded-2xl rounded-tl-sm bg-gradient-to-b from-slate-900/90 via-teal-950/20 to-slate-900/80 border border-teal-500/25 p-4 sm:p-5 shadow-xl shadow-slate-950/40 backdrop-blur-md relative transition-all group">
        {/* Top Header */}
        <div className="flex items-center justify-between mb-3 pb-2 border-b border-slate-800/60">
          <div className="flex items-center gap-2.5">
            <div className="w-7 h-7 rounded-xl bg-gradient-to-tr from-teal-400 to-cyan-400 flex items-center justify-center text-xs shadow-md shadow-teal-500/25 text-slate-950 font-bold">
              🌴
            </div>
            <div>
              <span className="text-xs font-bold text-teal-300 tracking-wide">
                TravelWise Guide
              </span>
              <span className="ml-2 text-[10px] font-semibold text-slate-400 uppercase tracking-wider px-1.5 py-0.5 rounded bg-slate-800/60 border border-slate-700/50">
                AI Bản Địa
              </span>
            </div>
          </div>

          {/* Action buttons: Replay sound & Copy */}
          <div className="flex items-center gap-1.5">
            <button
              type="button"
              onClick={handleCopy}
              className="p-1.5 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 transition-colors"
              title="Sao chép nội dung"
            >
              {copied ? (
                <span className="text-xs text-teal-400">✓ Đã chép</span>
              ) : (
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              )}
            </button>

            {/* Replay Audio Button with Equalizer Waveform */}
            <button
              type="button"
              onClick={handleReplayTTS}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold border transition-all cursor-pointer ${
                isPlaying
                  ? "bg-rose-500/20 text-rose-300 border-rose-500/40 shadow-sm shadow-rose-500/20"
                  : "bg-slate-800/90 text-teal-300 border-teal-500/30 hover:bg-teal-500/20 hover:border-teal-400/50"
              }`}
              title={isPlaying ? "Dừng giọng đọc AI" : "Nghe lại câu trả lời"}
            >
              {isPlaying ? (
                <>
                  <div className="flex items-center gap-0.5 h-3">
                    <span className="w-0.5 h-2 bg-rose-400 animate-bounce [animation-delay:-0.2s]"></span>
                    <span className="w-0.5 h-3 bg-rose-400 animate-bounce"></span>
                    <span className="w-0.5 h-1.5 bg-rose-400 animate-bounce [animation-delay:-0.4s]"></span>
                  </div>
                  <span>Dừng</span>
                </>
              ) : (
                <>
                  <span className="text-[11px]">▶</span>
                  <span>Nghe lại</span>
                </>
              )}
            </button>
          </div>
        </div>

        {/* Message Content */}
        <div className="text-[14.5px] text-slate-100 leading-relaxed font-normal whitespace-pre-wrap pl-1">
          {message.content}
        </div>

        {/* Proposal Card nếu có */}
        {message.proposal && (
          <div className="mt-4 p-3.5 rounded-xl bg-slate-900/90 border border-teal-500/30 shadow-md">
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
              <div>
                <p className="text-xs font-bold text-slate-100 flex items-center gap-1.5">
                  <span className="text-teal-400">✨</span>
                  <span>Lịch trình gợi ý: {message.proposal.destination} ({message.proposal.durationDays || 3} ngày)</span>
                </p>
                <p className="text-[11px] text-slate-400 mt-0.5">
                  Nhấn nút bên dưới hoặc nói &ldquo;Tạo lịch trình đi&rdquo; để lập kế hoạch chi tiết
                </p>
              </div>
              {onGenerateProposal && (
                <button
                  type="button"
                  onClick={() => onGenerateProposal(message.proposal)}
                  className="px-3.5 py-1.5 rounded-lg text-xs font-bold bg-gradient-to-r from-teal-400 to-cyan-400 text-slate-950 hover:brightness-105 active:scale-95 shadow-md shadow-teal-500/25 cursor-pointer transition-all flex-shrink-0"
                >
                  Tạo kế hoạch ngay →
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
