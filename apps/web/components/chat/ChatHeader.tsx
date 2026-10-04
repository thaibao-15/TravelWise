"use client";

import React from "react";

interface ChatHeaderProps {
  onClearHistory: () => void;
  messageCount: number;
}

export function ChatHeader({ onClearHistory, messageCount }: ChatHeaderProps) {
  return (
    <header className="sticky top-0 z-20 flex items-center justify-between px-6 py-4 bg-slate-900/80 backdrop-blur-xl border-b border-slate-800/80 shadow-lg">
      <div className="flex items-center gap-3">
        {/* Brand Icon Badge */}
        <div className="relative flex items-center justify-center w-10 h-10 rounded-xl bg-gradient-to-tr from-teal-500 to-emerald-400 text-slate-950 font-bold shadow-md shadow-teal-500/20">
          <svg
            className="w-6 h-6 text-slate-950"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              d="M13 10V3L4 14h7v7l9-11h-7z"
            />
          </svg>
          <span className="absolute -bottom-0.5 -right-0.5 flex h-3 w-3">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500 border-2 border-slate-900"></span>
          </span>
        </div>

        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-base font-semibold text-slate-100 tracking-wide">
              TravelWise AI Assistant
            </h1>
            <span className="px-2 py-0.5 text-[10px] font-medium tracking-wider uppercase rounded-full bg-teal-500/10 text-teal-400 border border-teal-500/20">
              RAG Powered
            </span>
          </div>
          <p className="text-xs text-slate-400">
            Hỏi đáp tri thức du lịch & gợi ý lịch trình thông minh
          </p>
        </div>
      </div>

      {/* Header Actions */}
      <div className="flex items-center gap-2">
        {messageCount > 1 && (
          <button
            onClick={onClearHistory}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-slate-400 hover:text-slate-200 bg-slate-800/60 hover:bg-slate-800 border border-slate-700/60 rounded-lg transition-all duration-200"
            title="Xóa lịch sử cuộc trò chuyện"
          >
            <svg
              className="w-3.5 h-3.5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
            <span className="hidden sm:inline">Làm mới</span>
          </button>
        )}
      </div>
    </header>
  );
}
