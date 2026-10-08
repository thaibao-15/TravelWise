"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import { UserService } from "@/services/user.service";
import { UserConversation } from "@/types/auth";

export default function ProfilePage() {
  const router = useRouter();
  const { user, isAuthenticated, isLoading, logout, refreshUser } = useAuth();

  const [activeTab, setActiveTab] = useState<"profile" | "history">("profile");

  // Form states
  const [fullName, setFullName] = useState("");
  const [avatarUrl, setAvatarUrl] = useState("");
  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Conversations state
  const [conversations, setConversations] = useState<UserConversation[]>([]);
  const [loadingConversations, setLoadingConversations] = useState(false);
  const [deletingId, setDeletingId] = useState<number | null>(null);

  // Sync state when user is loaded
  useEffect(() => {
    if (user) {
      setFullName(user.full_name || "");
      setAvatarUrl(user.avatar_url || "");
    }
  }, [user]);

  // Load conversations when tab changes
  useEffect(() => {
    if (isAuthenticated && activeTab === "history") {
      loadConversations();
    }
  }, [isAuthenticated, activeTab]);

  const loadConversations = async () => {
    try {
      setLoadingConversations(true);
      const data = await UserService.getConversations();
      setConversations(data);
    } catch (err) {
      console.error("Failed to load conversations", err);
    } finally {
      setLoadingConversations(false);
    }
  };

  const handleUpdateProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;

    setIsSaving(true);
    setSaveSuccess(null);
    setSaveError(null);

    try {
      await UserService.updateProfile(user.id, {
        full_name: fullName.trim() || null,
        avatar_url: avatarUrl.trim() || null,
      });
      await refreshUser();
      setSaveSuccess("Cập nhật thông tin thành công!");
      setIsEditing(false);
      setTimeout(() => setSaveSuccess(null), 3000);
    } catch (err: unknown) {
      if (err instanceof Error) {
        setSaveError(err.message);
      } else {
        setSaveError("Có lỗi xảy ra khi lưu thông tin.");
      }
    } finally {
      setIsSaving(false);
    }
  };

  const handleDeleteConversation = async (conversationId: number) => {
    if (!window.confirm("Bạn có chắc chắn muốn xóa cuộc trò chuyện này?")) return;

    try {
      setDeletingId(conversationId);
      await UserService.deleteConversation(conversationId);
      setConversations((prev) => prev.filter((c) => c.id !== conversationId));
    } catch (err) {
      console.error("Failed to delete conversation", err);
      alert("Không thể xóa cuộc trò chuyện. Vui lòng thử lại.");
    } finally {
      setDeletingId(null);
    }
  };

  const formatDate = (dateString?: string | null) => {
    if (!dateString) return "N/A";
    try {
      const date = new Date(dateString);
      return new Intl.DateTimeFormat("vi-VN", {
        day: "2-digit",
        month: "2-digit",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }).format(date);
    } catch {
      return dateString;
    }
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center text-teal-400 gap-3">
        <svg className="w-10 h-10 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          />
        </svg>
        <span className="text-sm font-medium text-slate-400">Đang tải hồ sơ...</span>
      </div>
    );
  }

  if (!isAuthenticated || !user) {
    return (
      <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col items-center justify-center p-4">
        <div className="w-full max-w-md bg-slate-900/80 border border-slate-800 rounded-2xl p-8 text-center shadow-2xl backdrop-blur-xl">
          <div className="w-16 h-16 rounded-2xl bg-teal-500/10 border border-teal-500/20 text-teal-400 flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-white mb-2">Yêu cầu đăng nhập</h2>
          <p className="text-slate-400 text-sm mb-6">
            Bạn cần đăng nhập để xem và quản lý thông tin tài khoản cũng như lịch sử hỏi đáp AI của mình.
          </p>
          <div className="flex flex-col gap-3">
            <Link
              href="/login?redirect=/profile"
              className="w-full py-3 px-4 rounded-xl font-semibold text-sm text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:from-teal-300 hover:to-emerald-200 transition-all shadow-lg shadow-teal-500/20"
            >
              Đăng nhập ngay
            </Link>
            <Link
              href="/"
              className="w-full py-3 px-4 rounded-xl font-medium text-sm text-slate-400 hover:text-white bg-slate-800/40 hover:bg-slate-800 transition-colors border border-slate-700/50"
            >
              Quay lại Trang chủ
            </Link>
          </div>
        </div>
      </div>
    );
  }

  const initialLetter = (user.full_name || user.email)[0].toUpperCase();

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans selection:bg-teal-500/30 selection:text-teal-200">
      {/* Background Ambient Glows */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[800px] h-[350px] bg-gradient-to-b from-teal-500/10 via-cyan-500/5 to-transparent blur-3xl pointer-events-none -z-10" />

      {/* Navigation Header */}
      <header className="sticky top-0 z-40 backdrop-blur-xl bg-slate-950/70 border-b border-slate-800/80">
        <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
          <Link href="/" className="flex items-center gap-2.5 group">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-teal-500 to-emerald-400 flex items-center justify-center text-slate-950 font-bold shadow-md shadow-teal-500/20 group-hover:scale-105 transition-transform">
              <svg className="w-6 h-6 text-slate-950" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.2" d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
              </svg>
            </div>
            <div>
              <span className="text-lg font-bold tracking-tight bg-gradient-to-r from-white via-slate-100 to-teal-300 bg-clip-text text-transparent">
                TravelWise
              </span>
              <span className="hidden sm:inline-block ml-2 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider rounded bg-teal-500/10 text-teal-400 border border-teal-500/20">
                Hồ sơ cá nhân
              </span>
            </div>
          </Link>

          <nav className="flex items-center gap-3 sm:gap-6 text-sm">
            <Link href="/" className="text-slate-400 hover:text-white transition-colors">
              Trang chủ
            </Link>
            <Link href="/places" className="text-slate-400 hover:text-white transition-colors">
              Điểm đến
            </Link>
            <Link href="/chat" className="text-slate-400 hover:text-white transition-colors">
              Chat AI
            </Link>
            <button
              onClick={() => {
                logout();
                router.push("/");
              }}
              className="px-3 py-1.5 rounded-lg text-xs font-medium text-red-400 hover:text-white hover:bg-red-500/20 border border-red-500/20 transition-all"
            >
              Đăng xuất
            </button>
          </nav>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 max-w-5xl w-full mx-auto px-4 py-8 sm:py-12">
        {/* Profile Card Banner */}
        <div className="relative rounded-3xl bg-slate-900/80 border border-slate-800 p-6 sm:p-8 backdrop-blur-xl shadow-xl overflow-hidden mb-8">
          <div className="absolute top-0 right-0 w-80 h-80 bg-gradient-to-bl from-teal-500/15 via-emerald-500/5 to-transparent rounded-full blur-2xl pointer-events-none -z-10" />

          <div className="flex flex-col sm:flex-row items-center sm:items-start gap-6">
            {/* Avatar Display */}
            <div className="relative group">
              <div className="w-24 h-24 sm:w-28 sm:h-28 rounded-2xl bg-gradient-to-tr from-teal-500 via-emerald-400 to-cyan-300 p-0.5 shadow-xl shadow-teal-500/20">
                <div className="w-full h-full rounded-[14px] bg-slate-950 flex items-center justify-center overflow-hidden">
                  {user.avatar_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={user.avatar_url}
                      alt={user.full_name || "Avatar"}
                      className="w-full h-full object-cover"
                      onError={(e) => {
                        (e.target as HTMLElement).style.display = "none";
                      }}
                    />
                  ) : (
                    <span className="text-4xl font-extrabold bg-gradient-to-tr from-teal-400 to-emerald-300 bg-clip-text text-transparent">
                      {initialLetter}
                    </span>
                  )}
                </div>
              </div>
              <span className="absolute -bottom-1 -right-1 flex h-4 w-4">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-4 w-4 bg-emerald-500 border-2 border-slate-950"></span>
              </span>
            </div>

            {/* User Meta Info */}
            <div className="flex-1 text-center sm:text-left">
              <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3 mb-2">
                <h1 className="text-2xl sm:text-3xl font-bold text-white tracking-tight">
                  {user.full_name || "Khách du lịch TravelWise"}
                </h1>
                <div className="flex items-center justify-center sm:justify-start gap-2">
                  <span className="px-2.5 py-0.5 text-xs font-semibold rounded-full bg-teal-500/10 text-teal-400 border border-teal-500/20 uppercase tracking-wide">
                    {user.role}
                  </span>
                  <span className="px-2.5 py-0.5 text-xs font-medium rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                    Hoạt động
                  </span>
                </div>
              </div>

              <p className="text-sm text-slate-400 mb-4">{user.email}</p>

              <div className="flex flex-wrap items-center justify-center sm:justify-start gap-4 sm:gap-6 text-xs text-slate-400">
                <div className="flex items-center gap-1.5">
                  <svg className="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                  <span>Gia nhập: {formatDate(user.created_at)}</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <svg className="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <span>Cập nhật: {formatDate(user.updated_at)}</span>
                </div>
              </div>
            </div>

            {/* Quick Action Button */}
            <div className="flex sm:flex-col gap-2 w-full sm:w-auto">
              <Link
                href="/chat"
                className="flex-1 sm:flex-none flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl font-semibold text-xs sm:text-sm text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:from-teal-300 hover:to-emerald-200 transition-all shadow-md shadow-teal-500/20"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
                </svg>
                <span>Hỏi đáp AI</span>
              </Link>
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex items-center gap-3 border-b border-slate-800 mb-6">
          <button
            onClick={() => setActiveTab("profile")}
            className={`pb-3 px-2 text-sm font-semibold transition-all relative flex items-center gap-2 ${
              activeTab === "profile"
                ? "text-teal-400"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            </svg>
            <span>Thông tin cá nhân</span>
            {activeTab === "profile" && (
              <span className="absolute bottom-0 left-0 right-0 h-0.5 bg-gradient-to-r from-teal-400 to-emerald-300 rounded-full" />
            )}
          </button>

          <button
            onClick={() => setActiveTab("history")}
            className={`pb-3 px-2 text-sm font-semibold transition-all relative flex items-center gap-2 ${
              activeTab === "history"
                ? "text-teal-400"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span>Lịch sử hội thoại AI</span>
            {activeTab === "history" && (
              <span className="absolute bottom-0 left-0 right-0 h-0.5 bg-gradient-to-r from-teal-400 to-emerald-300 rounded-full" />
            )}
          </button>
        </div>

        {/* Tab 1: Profile Details & Edit */}
        {activeTab === "profile" && (
          <div className="bg-slate-900/80 border border-slate-800 rounded-2xl p-6 sm:p-8 backdrop-blur-xl shadow-xl">
            <div className="flex items-center justify-between mb-6 pb-4 border-b border-slate-800">
              <div>
                <h2 className="text-lg font-bold text-white">Chi tiết tài khoản</h2>
                <p className="text-xs text-slate-400 mt-0.5">
                  Cập nhật họ tên hiển thị và avatar liên kết với tài khoản
                </p>
              </div>

              {!isEditing ? (
                <button
                  type="button"
                  onClick={() => setIsEditing(true)}
                  className="flex items-center gap-1.5 px-3.5 py-1.5 text-xs font-semibold text-teal-400 bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 rounded-xl transition-all"
                >
                  <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                  </svg>
                  <span>Chỉnh sửa</span>
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => {
                    setIsEditing(false);
                    setFullName(user.full_name || "");
                    setAvatarUrl(user.avatar_url || "");
                    setSaveError(null);
                  }}
                  className="px-3.5 py-1.5 text-xs font-medium text-slate-400 hover:text-white bg-slate-800 rounded-xl transition-colors"
                >
                  Hủy bỏ
                </button>
              )}
            </div>

            {/* Feedback notifications */}
            {saveSuccess && (
              <div className="mb-6 p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 flex items-center gap-3 text-emerald-300 text-sm">
                <svg className="w-5 h-5 text-emerald-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" />
                </svg>
                <span>{saveSuccess}</span>
              </div>
            )}

            {saveError && (
              <div className="mb-6 p-4 rounded-xl bg-red-500/10 border border-red-500/30 flex items-center gap-3 text-red-300 text-sm">
                <svg className="w-5 h-5 text-red-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>{saveError}</span>
              </div>
            )}

            <form onSubmit={handleUpdateProfile} className="space-y-6">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                {/* Full Name */}
                <div>
                  <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2">
                    Họ và tên
                  </label>
                  {isEditing ? (
                    <input
                      type="text"
                      value={fullName}
                      onChange={(e) => setFullName(e.target.value)}
                      placeholder="Nhập họ và tên..."
                      className="w-full px-4 py-2.5 bg-slate-950 border border-slate-700/80 rounded-xl text-slate-100 text-sm focus:outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-500/20 transition-all"
                    />
                  ) : (
                    <div className="px-4 py-2.5 bg-slate-950/60 border border-slate-800/80 rounded-xl text-slate-200 text-sm">
                      {user.full_name || "Chưa thiết lập họ tên"}
                    </div>
                  )}
                </div>

                {/* Email (Readonly) */}
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider">
                      Địa chỉ Email
                    </label>
                    <span className="text-[10px] text-teal-400 font-medium">Bảo mật</span>
                  </div>
                  <div className="px-4 py-2.5 bg-slate-950/40 border border-slate-800/60 rounded-xl text-slate-400 text-sm flex items-center justify-between">
                    <span>{user.email}</span>
                    <span className="text-xs text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20">
                      Đã xác thực
                    </span>
                  </div>
                </div>

                {/* Avatar URL */}
                <div className="sm:col-span-2">
                  <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2">
                    Đường dẫn Ảnh đại diện (Avatar URL)
                  </label>
                  {isEditing ? (
                    <div>
                      <input
                        type="url"
                        value={avatarUrl}
                        onChange={(e) => setAvatarUrl(e.target.value)}
                        placeholder="https://example.com/avatar.jpg"
                        className="w-full px-4 py-2.5 bg-slate-950 border border-slate-700/80 rounded-xl text-slate-100 text-sm focus:outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-500/20 transition-all"
                      />
                      <p className="text-[11px] text-slate-500 mt-1.5">
                        Dán URL hình ảnh trực tiếp (JPG, PNG, WebP) từ Google Drive, Imgur hoặc dịch vụ lưu trữ ảnh.
                      </p>
                    </div>
                  ) : (
                    <div className="px-4 py-2.5 bg-slate-950/60 border border-slate-800/80 rounded-xl text-slate-400 text-sm truncate">
                      {user.avatar_url || "Mặc định (sử dụng chữ cái đầu)"}
                    </div>
                  )}
                </div>

                {/* Role and ID info */}
                <div>
                  <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2">
                    Vai trò hệ thống
                  </label>
                  <div className="px-4 py-2.5 bg-slate-950/60 border border-slate-800/80 rounded-xl text-slate-200 text-sm font-medium">
                    {user.role === "ADMIN" ? "Quản trị viên (Admin)" : "Thành viên du lịch (User)"}
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-2">
                    ID Tài khoản
                  </label>
                  <div className="px-4 py-2.5 bg-slate-950/60 border border-slate-800/80 rounded-xl text-slate-400 text-sm font-mono">
                    #{user.id}
                  </div>
                </div>
              </div>

              {isEditing && (
                <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                  <button
                    type="button"
                    onClick={() => {
                      setIsEditing(false);
                      setFullName(user.full_name || "");
                      setAvatarUrl(user.avatar_url || "");
                    }}
                    className="px-5 py-2.5 rounded-xl text-xs sm:text-sm font-medium text-slate-300 hover:text-white bg-slate-800 hover:bg-slate-700 transition-colors"
                  >
                    Hủy
                  </button>
                  <button
                    type="submit"
                    disabled={isSaving}
                    className="px-6 py-2.5 rounded-xl text-xs sm:text-sm font-semibold text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:from-teal-300 hover:to-emerald-200 transition-all shadow-md shadow-teal-500/20 disabled:opacity-50 flex items-center gap-2"
                  >
                    {isSaving ? (
                      <>
                        <svg className="w-4 h-4 animate-spin text-slate-950" fill="none" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                        </svg>
                        <span>Đang lưu...</span>
                      </>
                    ) : (
                      <span>Lưu thay đổi</span>
                    )}
                  </button>
                </div>
              )}
            </form>
          </div>
        )}

        {/* Tab 2: AI Conversation History */}
        {activeTab === "history" && (
          <div className="bg-slate-900/80 border border-slate-800 rounded-2xl p-6 sm:p-8 backdrop-blur-xl shadow-xl">
            <div className="flex items-center justify-between mb-6 pb-4 border-b border-slate-800">
              <div>
                <h2 className="text-lg font-bold text-white">Lịch sử cuộc trò chuyện AI</h2>
                <p className="text-xs text-slate-400 mt-0.5">
                  Các phiên hỏi đáp du lịch thông minh đã được lưu trữ an toàn trên hệ thống
                </p>
              </div>

              <Link
                href="/chat"
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:from-teal-300 hover:to-emerald-200 rounded-xl transition-all shadow-sm"
              >
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v16m8-8H4" />
                </svg>
                <span>Hội thoại mới</span>
              </Link>
            </div>

            {loadingConversations ? (
              <div className="py-12 flex flex-col items-center justify-center text-teal-400 gap-3">
                <svg className="w-8 h-8 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                </svg>
                <span className="text-xs text-slate-400">Đang tải lịch sử hội thoại...</span>
              </div>
            ) : conversations.length === 0 ? (
              <div className="py-12 text-center">
                <div className="w-16 h-16 rounded-2xl bg-slate-800/60 border border-slate-700/60 flex items-center justify-center mx-auto mb-3 text-slate-500">
                  <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                  </svg>
                </div>
                <h3 className="text-base font-semibold text-slate-200 mb-1">Chưa có cuộc trò chuyện nào</h3>
                <p className="text-xs text-slate-400 max-w-sm mx-auto mb-6">
                  Hãy bắt đầu trò chuyện với trợ lý du lịch AI để hỏi về địa điểm, giá vé, lịch trình tham quan.
                </p>
                <Link
                  href="/chat"
                  className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-semibold text-xs text-slate-950 bg-gradient-to-r from-teal-400 to-emerald-300 hover:from-teal-300 hover:to-emerald-200 transition-all shadow-md shadow-teal-500/20"
                >
                  <span>Bắt đầu cuộc trò chuyện đầu tiên</span>
                </Link>
              </div>
            ) : (
              <div className="divide-y divide-slate-800/80">
                {conversations.map((conv) => (
                  <div
                    key={conv.id}
                    className="py-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 group hover:bg-slate-800/20 px-2 rounded-xl transition-colors"
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-9 h-9 rounded-xl bg-teal-500/10 border border-teal-500/20 flex items-center justify-center text-teal-400 shrink-0 mt-0.5">
                        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
                        </svg>
                      </div>
                      <div>
                        <h4 className="text-sm font-semibold text-slate-200 group-hover:text-teal-300 transition-colors">
                          {conv.title || "Cuộc trò chuyện không tên"}
                        </h4>
                        <div className="flex items-center gap-3 text-[11px] text-slate-500 mt-1">
                          <span>Cập nhật: {formatDate(conv.updated_at)}</span>
                          <span>•</span>
                          <span>Tạo lúc: {formatDate(conv.created_at)}</span>
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 self-end sm:self-center">
                      <Link
                        href={`/chat?conversation_id=${conv.id}`}
                        className="px-3 py-1.5 rounded-lg text-xs font-medium text-teal-400 hover:text-teal-300 bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 transition-all flex items-center gap-1.5"
                      >
                        <span>Tiếp tục</span>
                        <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5l7 7-7 7" />
                        </svg>
                      </Link>

                      <button
                        onClick={() => handleDeleteConversation(conv.id)}
                        disabled={deletingId === conv.id}
                        className="p-1.5 rounded-lg text-slate-500 hover:text-red-400 hover:bg-red-500/10 transition-colors disabled:opacity-50"
                        title="Xóa cuộc trò chuyện này"
                      >
                        {deletingId === conv.id ? (
                          <svg className="w-4 h-4 animate-spin text-red-400" fill="none" viewBox="0 0 24 24">
                            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                          </svg>
                        ) : (
                          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                          </svg>
                        )}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}
