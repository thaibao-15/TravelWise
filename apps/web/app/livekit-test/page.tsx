"use client";

import React, { useState, useEffect, useCallback } from "react";
import Link from "next/link";
import { LiveKitVoicePanel } from "@/components/livekit/LiveKitVoicePanel";
import { livekitService } from "@/services/livekit.service";
import { LiveKitStatusResponse } from "@/types/livekit";

export default function LiveKitTestPage() {
  const [serverStatus, setServerStatus] = useState<LiveKitStatusResponse | null>(null);
  const [isLoadingStatus, setIsLoadingStatus] = useState(true);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [hasToken, setHasToken] = useState(false);
  const [manualToken, setManualToken] = useState("");
  const [customConversationId, setCustomConversationId] = useState<string>("");

  const checkAuthToken = useCallback(() => {
    if (typeof window !== "undefined") {
      const token =
        localStorage.getItem("travelwise_token") || localStorage.getItem("token");
      setHasToken(!!token && token.trim().length > 0);
    }
  }, []);

  const handleRefreshStatus = useCallback(async () => {
    setIsLoadingStatus(true);
    setStatusError(null);
    try {
      const res = await livekitService.getStatus();
      setServerStatus(res);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không thể kiểm tra trạng thái máy chủ";
      setStatusError(msg);
    } finally {
      setIsLoadingStatus(false);
    }
  }, []);

  useEffect(() => {
    let isCancelled = false;

    // Check auth token
    if (typeof window !== "undefined") {
      const token =
        localStorage.getItem("travelwise_token") || localStorage.getItem("token");
      if (token && token.trim().length > 0) {
        setTimeout(() => {
          if (!isCancelled) {
            setHasToken(true);
          }
        }, 0);
      }
    }

    // Load initial server status
    livekitService
      .getStatus()
      .then((res) => {
        if (!isCancelled) {
          setServerStatus(res);
          setIsLoadingStatus(false);
        }
      })
      .catch((err: unknown) => {
        if (!isCancelled) {
          const msg = err instanceof Error ? err.message : "Không thể kiểm tra trạng thái máy chủ";
          setStatusError(msg);
          setIsLoadingStatus(false);
        }
      });

    return () => {
      isCancelled = true;
    };
  }, []);

  const handleSaveToken = () => {
    if (!manualToken.trim()) return;
    localStorage.setItem("travelwise_token", manualToken.trim());
    setManualToken("");
    checkAuthToken();
  };

  const handleClearToken = () => {
    localStorage.removeItem("travelwise_token");
    localStorage.removeItem("token");
    checkAuthToken();
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 py-10 px-4 sm:px-6">
      <div className="max-w-4xl mx-auto space-y-8">
        {/* Navigation Breadcrumb */}
        <div className="flex items-center justify-between">
          <Link
            href="/chat"
            className="inline-flex items-center gap-2 text-xs font-medium text-teal-400 hover:text-teal-300 transition-colors"
          >
            <span>←</span> Quay lại Chat Du lịch
          </Link>
          <div className="text-xs px-2.5 py-1 rounded-full bg-teal-500/10 border border-teal-500/30 text-teal-400 font-mono">
            Phase 3: Frontend WebRTC Layer
          </div>
        </div>

        {/* Page Title */}
        <div className="space-y-2">
          <h1 className="text-2xl sm:text-3xl font-bold bg-gradient-to-r from-teal-400 via-cyan-400 to-sky-500 bg-clip-text text-transparent">
            Kiểm Thử Kết Nối LiveKit Voice WebRTC
          </h1>
          <p className="text-sm text-slate-400">
            Trang chẩn đoán và thử nghiệm riêng biệt cho kết nối LiveKit Cloud, cấp token và điều khiển luồng microphone.
          </p>
        </div>

        {/* Diagnostic Status Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {/* Backend Status Card */}
          <div className="p-4 bg-slate-900/60 border border-slate-800 rounded-2xl space-y-2.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-300">
                1. Trạng thái Backend FastAPI
              </span>
              <button
                onClick={handleRefreshStatus}
                className="text-xs text-teal-400 hover:underline"
              >
                Làm mới
              </button>
            </div>
            {isLoadingStatus ? (
              <div className="text-xs text-slate-500 animate-pulse">
                Đang kiểm tra /api/v1/livekit/status...
              </div>
            ) : statusError ? (
              <div className="text-xs text-rose-400 font-medium">
                ❌ {statusError}
              </div>
            ) : serverStatus?.is_configured ? (
              <div className="space-y-1">
                <div className="text-xs text-emerald-400 font-medium flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-emerald-400" />
                  LiveKit Cloud đã sẵn sàng
                </div>
                <div className="text-[11px] text-slate-400 font-mono truncate">
                  URL: {serverStatus.server_url}
                </div>
                <div className="text-[11px] text-slate-400">
                  Agent: <span className="text-slate-300 font-mono">{serverStatus.agent_name}</span>
                </div>
              </div>
            ) : (
              <div className="text-xs text-amber-400">
                ⚠️ Backend chưa cấu hình LiveKit credentials.
              </div>
            )}
          </div>

          {/* Authentication Status Card */}
          <div className="p-4 bg-slate-900/60 border border-slate-800 rounded-2xl space-y-2.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-300">
                2. Trạng thái Xác thực Người dùng
              </span>
              {hasToken && (
                <button
                  onClick={handleClearToken}
                  className="text-xs text-rose-400 hover:underline"
                >
                  Xóa Token
                </button>
              )}
            </div>
            {hasToken ? (
              <div className="space-y-1">
                <div className="text-xs text-emerald-400 font-medium flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-emerald-400" />
                  Đã đăng nhập (Có travelwise_token)
                </div>
                <p className="text-[11px] text-slate-400">
                  Sẵn sàng gửi header Bearer để lấy LiveKit Access Token.
                </p>
              </div>
            ) : (
              <div className="space-y-2">
                <div className="text-xs text-amber-400 flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-amber-400" />
                  Chưa tìm thấy Token trong trình duyệt
                </div>
                <div className="flex gap-2">
                  <input
                    type="password"
                    placeholder="Dán JWT Token vào đây để test..."
                    value={manualToken}
                    onChange={(e) => setManualToken(e.target.value)}
                    className="flex-1 bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1 text-xs text-slate-200 placeholder:text-slate-600 focus:outline-none focus:border-teal-500"
                  />
                  <button
                    onClick={handleSaveToken}
                    className="px-3 py-1 bg-teal-600 hover:bg-teal-500 text-white rounded-lg text-xs font-medium"
                  >
                    Lưu
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Optional Conversation ID configuration */}
        <div className="p-4 bg-slate-900/40 border border-slate-800/80 rounded-2xl flex flex-wrap items-center justify-between gap-3 text-xs">
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Tùy chọn Conversation ID:</span>
            <input
              type="number"
              placeholder="Tự sinh mới nếu để trống"
              value={customConversationId}
              onChange={(e) => setCustomConversationId(e.target.value)}
              className="w-48 bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1 text-slate-200 placeholder:text-slate-600 focus:outline-none focus:border-teal-500"
            />
          </div>
          <span className="text-slate-500">
            Nếu để trống, backend sẽ tự động tạo cuộc trò chuyện mới.
          </span>
        </div>

        {/* Main LiveKit Voice Panel Component */}
        <LiveKitVoicePanel
          conversationId={customConversationId ? parseInt(customConversationId, 10) : undefined}
        />

        {/* Testing Guide Section */}
        <div className="p-5 bg-slate-900/40 border border-slate-800/80 rounded-2xl text-xs space-y-3 text-slate-400">
          <h4 className="font-semibold text-slate-200 text-sm">
            📋 Hướng dẫn kiểm thử Giai đoạn 3 (Frontend Layer):
          </h4>
          <ol className="list-decimal pl-5 space-y-1.5 leading-relaxed">
            <li>
              Đảm bảo backend FastAPI đang chạy tại{" "}
              <code className="text-teal-300 font-mono">http://localhost:8000</code> và đã cấu hình LiveKit keys trong{" "}
              <code className="text-teal-300 font-mono">.env</code>.
            </li>
            <li>
              Đăng nhập tài khoản trên TravelWise hoặc dán JWT Token vào ô kiểm tra xác thực phía trên.
            </li>
            <li>
              Nhấn <strong>Kết nối phòng LiveKit</strong> để kiểm tra luồng gọi API{" "}
              <code className="text-teal-300 font-mono">POST /api/v1/livekit/token</code> và bắt tay WebRTC.
            </li>
            <li>
              Nhấn <strong>Bật Micro</strong> để kiểm tra hộp thoại xin quyền microphone của trình duyệt và xem log WebRTC.
            </li>
            <li>
              Nhấn <strong>Rời phòng thoại</strong> để kiểm tra khả năng dọn dẹp track âm thanh và ngắt kết nối an toàn.
            </li>
          </ol>
        </div>
      </div>
    </div>
  );
}
