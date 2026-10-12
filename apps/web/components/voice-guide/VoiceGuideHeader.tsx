"use client";

import React from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";

interface VoiceGuideHeaderProps {
  onClearHistory: () => void;
  onOpenTextInput?: () => void;
  isCanvasOpen: boolean;
  onToggleCanvas: () => void;
}

export function VoiceGuideHeader({
  onClearHistory,
  onOpenTextInput,
  isCanvasOpen,
  onToggleCanvas,
}: VoiceGuideHeaderProps) {
  const { user, isAuthenticated, logout } = useAuth();
  const searchParams = useSearchParams();
  const conversationId = searchParams.get("conversation_id");

  const chatUrl = conversationId ? `/chat?conversation_id=${conversationId}` : "/chat";
  const voiceGuideUrl = conversationId
    ? `/voice-guide?conversation_id=${conversationId}`
    : "/voice-guide";

  return (
    <header className="sticky top-0 z-30 flex items-center justify-between px-3 sm:px-6 py-2.5 sm:py-3 bg-slate-900/90 backdrop-blur-xl border-b border-slate-800/80 shadow-md">
      {/* 1. Left: Brand Title */}
      <div className="flex items-center gap-3 min-w-0">
        <Link
          href="/"
          className="relative flex items-center justify-center w-10 h-10 rounded-2xl bg-gradient-to-tr from-teal-400 to-cyan-400 text-slate-950 font-bold shadow-md shadow-teal-500/20 hover:scale-105 transition-transform flex-shrink-0"
          title="Trang chủ TravelWise"
        >
          <span className="text-xl">🌴</span>
          <span className="absolute -bottom-0.5 -right-0.5 w-3 h-3 bg-teal-400 rounded-full border-2 border-slate-900 animate-pulse" />
        </Link>

        <div className="min-w-0 hidden md:block">
          <div className="flex items-center gap-2">
            <h1 className="text-sm font-bold text-slate-100 tracking-wide truncate">
              TravelWise Guide
            </h1>
            <span className="px-2 py-0.5 text-[10px] font-bold tracking-wider uppercase rounded-full bg-teal-500/10 text-teal-300 border border-teal-500/20">
              VOICE CHAT
            </span>
          </div>
          <p className="text-[11px] text-slate-400 truncate">
            Hướng dẫn viên bản địa trực tiếp qua giọng nói
          </p>
        </div>
      </div>

      {/* 2. Center: Segmented Switcher for 2 Chat Modes (Chat Box & Voice Chat) */}
      <nav
        aria-label="Chuyển đổi chế độ trò chuyện"
        className="flex items-center p-1 rounded-xl bg-slate-950/80 border border-slate-800 shadow-inner"
      >
        {/* Tab 1: Chat Box (Switchable) */}
        <Link
          href={chatUrl}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold text-slate-400 hover:text-teal-300 hover:bg-slate-800/60 active:scale-95 transition-all group"
          title="Chuyển sang chế độ Chat Văn bản"
        >
          <span>💬</span>
          <span>Chat Box</span>
        </Link>

        {/* Tab 2: Voice Chat (Active) */}
        <Link
          href={voiceGuideUrl}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold bg-gradient-to-r from-teal-400 via-cyan-400 to-teal-400 text-slate-950 shadow-md shadow-teal-400/25 transition-all cursor-default"
          title="Đang ở chế độ Voice Chat chuyên biệt"
        >
          <span className="relative flex h-2 w-2">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-slate-950 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-slate-950"></span>
          </span>
          <span className="text-sm">🎙️</span>
          <span>Voice Chat</span>
        </Link>
      </nav>

      {/* 3. Right: Action Buttons */}
      <div className="flex items-center gap-1 sm:gap-2">
        {/* Làm mới Button */}
        <button
          type="button"
          onClick={onClearHistory}
          className="flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 text-xs font-medium text-slate-300 hover:text-slate-100 bg-slate-800/60 hover:bg-slate-800 border border-slate-700/60 rounded-xl transition-all cursor-pointer"
          title="Làm mới cuộc trò chuyện"
        >
          <span>🔄</span>
          <span className="hidden lg:inline">Làm mới</span>
        </button>

        {/* Nút chuyển qua Chat Box */}
        <Link
          href={chatUrl}
          className="flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 text-xs font-bold text-slate-100 hover:text-white bg-slate-800/90 hover:bg-slate-750 border border-slate-700/90 hover:border-teal-400/50 rounded-xl shadow-sm transition-all active:scale-95 group"
          title="Chuyển sang Chat Box (Chat bằng văn bản)"
        >
          <span className="text-sm group-hover:scale-110 transition-transform">💬</span>
          <span>Chat Box</span>
        </Link>

        {/* Kế hoạch Button */}
        <button
          type="button"
          onClick={onToggleCanvas}
          className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-xl border transition-all cursor-pointer shadow-sm ${
            isCanvasOpen
              ? "bg-teal-400 text-slate-950 border-teal-400 shadow-teal-400/30"
              : "bg-slate-800/70 text-slate-300 border-slate-700/70 hover:border-teal-500/40 hover:text-teal-300"
          }`}
          title="Bật/Tắt bảng Kế hoạch & Lịch trình bên phải"
        >
          <span>🗺️</span>
          <span className="hidden sm:inline">Kế hoạch</span>
        </button>

        {/* Home Link */}
        <Link
          href="/"
          className="flex items-center gap-1 px-2.5 py-1.5 text-xs text-slate-400 hover:text-slate-200 bg-slate-800/40 hover:bg-slate-800 border border-slate-700/50 rounded-xl transition-all"
          title="Trang chủ"
        >
          <span>🏠</span>
        </Link>

        {/* User Auth Info */}
        {isAuthenticated && user ? (
          <div className="flex items-center gap-1.5">
            <Link
              href="/profile"
              className="flex items-center gap-1.5 px-2 py-1 rounded-xl bg-slate-800 hover:bg-slate-750 border border-slate-700/60 text-xs text-slate-200 transition-all group"
              title="Thông tin cá nhân"
            >
              <div className="w-5 h-5 rounded-full bg-teal-500/20 text-teal-400 font-bold flex items-center justify-center text-[10px] border border-teal-500/30">
                {(user.full_name || user.email)[0].toUpperCase()}
              </div>
              <span className="hidden xl:inline max-w-[80px] truncate font-medium">
                {user.full_name || user.email}
              </span>
            </Link>
            <button
              type="button"
              onClick={logout}
              className="hidden md:inline px-2 py-1 text-xs text-slate-400 hover:text-rose-400 bg-slate-800/40 hover:bg-slate-800 border border-slate-700/50 rounded-xl transition-colors cursor-pointer"
              title="Đăng xuất"
            >
              Thoát
            </button>
          </div>
        ) : (
          <Link
            href="/login?redirect=/voice-guide"
            className="flex items-center gap-1 px-2.5 sm:px-3 py-1.5 text-xs font-semibold text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:brightness-105 rounded-xl shadow-sm shadow-teal-500/20 transition-all"
          >
            Đăng nhập
          </Link>
        )}
      </div>
    </header>
  );
}
