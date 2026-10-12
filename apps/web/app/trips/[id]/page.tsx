"use client";

import React, { useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useItinerary } from "@/hooks/useItinerary";
import { ItineraryTimeline } from "@/components/itinerary/ItineraryTimeline";

export default function TripDetailPage() {
  const params = useParams();
  const tripIdStr = params?.id as string;
  const tripId = tripIdStr ? parseInt(tripIdStr, 10) : null;

  const {
    itinerary,
    isLoading,
    isEditing,
    error,
    editItinerary,
    confirmTrip,
  } = useItinerary(tripId);

  const [editPrompt, setEditPrompt] = useState("");
  const [editFeedback, setEditFeedback] = useState<string | null>(null);

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editPrompt.trim() || !tripId || isEditing) return;

    try {
      const res = await editItinerary(tripId, { change_prompt: editPrompt.trim() });
      setEditFeedback(res.message);
      setEditPrompt("");
      setTimeout(() => setEditFeedback(null), 5000);
    } catch {
      // Handled by hook error
    }
  };

  const handleTimelinePrompt = (prompt: string) => {
    setEditPrompt(prompt);
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans">
      {/* Top Header */}
      <header className="sticky top-0 z-20 flex items-center justify-between px-6 py-4 bg-slate-900/80 backdrop-blur-xl border-b border-slate-800">
        <div className="flex items-center gap-3">
          <Link
            href="/trips"
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition-colors"
            title="Quay lại danh sách chuyến đi"
          >
            ←
          </Link>
          <div className="flex items-center gap-2">
            <span className="font-bold text-base text-slate-200">
              {itinerary?.name || `Chi tiết Chuyến đi #${tripId}`}
            </span>
            {itinerary?.status && (
              <span className={`text-[10px] font-extrabold px-2 py-0.5 rounded uppercase tracking-wider ${
                itinerary.status === "CONFIRMED"
                  ? "bg-emerald-500/20 text-emerald-300 border border-emerald-500/40"
                  : "bg-teal-500/10 text-teal-300 border border-teal-500/20"
              }`}>
                {itinerary.status}
              </span>
            )}
          </div>
        </div>

        <div className="flex items-center gap-3">
          {tripId && itinerary?.status !== "CONFIRMED" && (
            <button
              type="button"
              onClick={async () => {
                await confirmTrip(tripId);
                setEditFeedback("Đã chốt lịch trình thành công! Chúc bạn có một chuyến đi tuyệt vời!");
                setTimeout(() => setEditFeedback(null), 5000);
              }}
              className="px-3.5 py-1.5 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 text-slate-950 text-xs font-bold hover:brightness-110 active:scale-95 transition-all shadow-md cursor-pointer"
            >
              ✅ Chốt lịch trình
            </button>
          )}

          <Link
            href="/chat"
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-750 text-teal-300 text-xs font-semibold border border-slate-700 transition-colors"
          >
            <span>💬</span>
            <span>Mở trong AI Tour Guide</span>
          </Link>
        </div>
      </header>

      {/* Main Body */}
      <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {isLoading ? (
          <div className="space-y-4">
            <div className="h-32 rounded-2xl bg-slate-900 border border-slate-800 animate-pulse" />
            <div className="h-96 rounded-2xl bg-slate-900 border border-slate-800 animate-pulse" />
          </div>
        ) : error ? (
          <div className="p-6 rounded-2xl bg-rose-950/40 border border-rose-900/60 text-center space-y-3">
            <p className="text-sm font-semibold text-rose-300">{error}</p>
            <Link
              href="/trips"
              className="inline-block px-4 py-2 rounded-xl bg-slate-800 text-xs font-semibold text-slate-200"
            >
              Quay lại danh sách chuyến đi
            </Link>
          </div>
        ) : itinerary ? (
          <div className="space-y-6">
            {/* Timeline View */}
            <ItineraryTimeline
              itinerary={itinerary}
              onEditPrompt={handleTimelinePrompt}
            />

            {/* Conversational Edit Form */}
            <div className="p-5 rounded-2xl bg-slate-900/90 border border-slate-800 shadow-xl">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-base">✨</span>
                <h3 className="text-sm font-bold text-slate-200">
                  Chỉnh sửa lịch trình bằng Trợ lý AI
                </h3>
              </div>
              <p className="text-xs text-slate-400 mb-3">
                Bạn có thể yêu cầu đổi địa điểm, thêm quán ăn đặc sản, hoặc thay đổi nhịp độ chuyến đi bằng ngôn ngữ tự nhiên.
              </p>

              {editFeedback && (
                <div className="mb-3 p-3 rounded-xl bg-teal-500/10 border border-teal-500/30 text-teal-300 text-xs animate-in fade-in">
                  🎉 {editFeedback}
                </div>
              )}

              <form onSubmit={handleEditSubmit} className="flex gap-2">
                <input
                  type="text"
                  value={editPrompt}
                  onChange={(e) => setEditPrompt(e.target.value)}
                  placeholder="Ví dụ: Ngày 2 đổi sang đi tắm biển Mỹ Khê và ăn hải sản..."
                  disabled={isEditing}
                  className="flex-1 px-4 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-200 placeholder-slate-500 focus:outline-none focus:border-teal-500"
                />
                <button
                  type="submit"
                  disabled={isEditing || !editPrompt.trim()}
                  className="px-5 py-2.5 rounded-xl bg-gradient-to-r from-teal-500 to-cyan-500 text-slate-950 text-xs font-bold shadow-md shadow-teal-900/30 hover:brightness-110 active:scale-[0.98] transition-all cursor-pointer disabled:opacity-50"
                >
                  {isEditing ? "Đang xử lý..." : "Cập nhật"}
                </button>
              </form>
            </div>
          </div>
        ) : (
          <div className="p-12 text-center text-slate-500 text-xs">
            Không tìm thấy thông tin lịch trình.
          </div>
        )}
      </main>
    </div>
  );
}
