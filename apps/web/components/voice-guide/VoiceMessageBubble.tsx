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
  const audioRef = useRef<HTMLAudioElement | null>(null);

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
      <div className="w-full max-w-2xl mx-auto rounded-2xl bg-slate-900/70 border border-slate-800/80 p-4 transition-all">
        {/* Header: Mic Icon + Bạn */}
        <div className="flex items-center gap-2 mb-2">
          <div className="w-6 h-6 rounded-full bg-slate-800 border border-slate-700/60 flex items-center justify-center text-xs text-slate-300">
            🎙️
          </div>
          <span className="text-xs font-semibold text-slate-300">Bạn</span>
        </div>

        {/* Content */}
        <p className="text-sm text-slate-100 font-medium leading-relaxed pl-8">
          {message.content}
        </p>
      </div>
    );
  }

  // Assistant Message: TravelWise Guide
  return (
    <div className="w-full max-w-2xl mx-auto rounded-2xl bg-teal-950/20 border border-teal-500/20 p-4 sm:p-5 transition-all relative">
      {/* Header: Palm tree + TravelWise Guide + Button "Nghe lại" */}
      <div className="flex items-center justify-between mb-2.5">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-full bg-teal-500/20 border border-teal-500/30 flex items-center justify-center text-xs shadow-sm">
            🌴
          </div>
          <span className="text-xs font-bold text-teal-300 tracking-wide">
            TravelWise Guide
          </span>
        </div>

        {/* Button: ▶ Nghe lại */}
        <button
          type="button"
          onClick={handleReplayTTS}
          className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium border transition-all cursor-pointer ${
            isPlaying
              ? "bg-rose-500/20 text-rose-300 border-rose-500/40 animate-pulse"
              : "bg-slate-800/80 text-teal-300 border-teal-500/30 hover:bg-teal-500/20"
          }`}
          title={isPlaying ? "Dừng phát giọng nói" : "Nghe lại câu trả lời bằng giọng nói"}
        >
          <span>{isPlaying ? "⏹" : "▶"}</span>
          <span>{isPlaying ? "Dừng" : "Nghe lại"}</span>
        </button>
      </div>

      {/* Content */}
      <div className="text-sm text-slate-100 leading-relaxed pl-9 whitespace-pre-wrap font-normal">
        {message.content}
      </div>

      {/* Proposal Card nếu có */}
      {message.proposal && (
        <div className="mt-3 ml-9 p-3.5 rounded-xl bg-slate-900/80 border border-teal-500/30">
          <div className="flex items-center justify-between gap-2">
            <div>
              <p className="text-xs font-bold text-slate-100">
                ✨ Lịch trình đề xuất: {message.proposal.destination} ({message.proposal.durationDays || 3} ngày)
              </p>
              <p className="text-[11px] text-slate-400">
                Nhấn bên dưới hoặc nói &ldquo;Tạo lịch trình đi&rdquo; để bắt đầu
              </p>
            </div>
            {onGenerateProposal && (
              <button
                type="button"
                onClick={() => onGenerateProposal(message.proposal)}
                className="px-3 py-1.5 rounded-lg text-xs font-bold bg-teal-400 text-slate-950 hover:bg-teal-300 cursor-pointer transition-all"
              >
                Tạo ngay
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
