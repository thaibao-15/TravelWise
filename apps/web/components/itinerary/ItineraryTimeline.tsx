"use client";

import React, { useState } from "react";
import { ItineraryDetail } from "@/hooks/useItinerary";

interface ItineraryTimelineProps {
  itinerary: ItineraryDetail;
  onEditPrompt?: (prompt: string) => void;
}

export function ItineraryTimeline({
  itinerary,
  onEditPrompt,
}: ItineraryTimelineProps) {
  const [activeDayIndex, setActiveDayIndex] = useState(0);

  const days = itinerary?.days || [];
  const activeDay = days[activeDayIndex] || days[0];

  return (
    <div className="rounded-2xl bg-slate-900/80 border border-slate-800 p-6 shadow-xl backdrop-blur-sm">
      {/* Overview Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-6 border-b border-slate-800 gap-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xl">🗺️</span>
            <h2 className="text-xl font-bold text-slate-100">
              {itinerary.name || `Lịch trình du lịch ${itinerary.destination_city || ""}`}
            </h2>
          </div>
          <p className="text-xs text-slate-400 mt-1">
            📍 Điểm đến:{" "}
            <span className="text-teal-400 font-semibold">
              {itinerary.destination_city || "Việt Nam"}
            </span>{" "}
            • ⏱️ Thời lượng:{" "}
            <span className="text-teal-400 font-semibold">
              {itinerary.days_count || days.length} ngày
            </span>
          </p>
        </div>

        {/* Quick Suggestion Pills */}
        {onEditPrompt && (
          <div className="flex flex-wrap gap-1.5">
            {[
              "🌊 Thêm buổi chiều tắm biển",
              "🍜 Thêm món ăn đặc sản địa phương",
              "☕ Thêm quán cafe ngắm hoàng hôn",
            ].map((chip) => (
              <button
                key={chip}
                type="button"
                onClick={() => onEditPrompt(chip)}
                className="px-2.5 py-1 rounded-lg bg-teal-500/10 hover:bg-teal-500/20 text-teal-300 text-[11px] font-medium border border-teal-500/20 transition-all cursor-pointer"
              >
                {chip}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Day Selector Tabs */}
      {days.length > 1 && (
        <div className="flex items-center gap-2 py-4 border-b border-slate-800 overflow-x-auto custom-scrollbar">
          {days.map((day, idx) => (
            <button
              key={day.id || idx}
              type="button"
              onClick={() => setActiveDayIndex(idx)}
              className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap flex items-center gap-2 ${
                activeDayIndex === idx
                  ? "bg-gradient-to-r from-teal-500 to-cyan-500 text-slate-950 shadow-md shadow-teal-900/30 font-extrabold"
                  : "bg-slate-800/80 hover:bg-slate-800 text-slate-400 hover:text-slate-200 border border-slate-700/60"
              }`}
            >
              <span>Ngày {day.day_number || idx + 1}</span>
              {day.theme && (
                <span className="text-[10px] opacity-80 font-normal">
                  • {day.theme}
                </span>
              )}
            </button>
          ))}
        </div>
      )}

      {/* Day Activities List */}
      <div className="pt-6">
        {activeDay ? (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold text-teal-300 flex items-center gap-2">
                <span>🗓️</span>
                <span>
                  Ngày {activeDay.day_number}: {activeDay.title || activeDay.theme || "Khám phá địa điểm"}
                </span>
              </h3>
              {activeDay.notes && (
                <span className="text-[11px] text-slate-400 italic">
                  💡 {activeDay.notes}
                </span>
              )}
            </div>

            {/* Activities Timeline */}
            <div className="relative pl-6 space-y-6 before:absolute before:left-2 before:top-2 before:bottom-2 before:w-0.5 before:bg-gradient-to-b before:from-teal-500 before:via-cyan-500 before:to-slate-800">
              {(activeDay.activities || []).map((act, actIdx) => (
                <div key={act.id || actIdx} className="relative group">
                  {/* Timeline bullet */}
                  <div className="absolute -left-6 top-1.5 w-4 h-4 rounded-full bg-slate-900 border-2 border-teal-400 flex items-center justify-center group-hover:scale-125 transition-transform">
                    <div className="w-1.5 h-1.5 rounded-full bg-teal-400" />
                  </div>

                  {/* Card item */}
                  <div className="p-4 rounded-xl bg-slate-800/60 hover:bg-slate-800 border border-slate-700/50 hover:border-teal-500/30 transition-all shadow-sm">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          {act.time_slot && (
                            <span className="text-[11px] font-bold px-2 py-0.5 rounded bg-teal-500/15 text-teal-300 border border-teal-500/25">
                              ⏰ {act.time_slot}
                            </span>
                          )}
                          <h4 className="text-sm font-bold text-slate-100 group-hover:text-teal-300 transition-colors">
                            {act.place_name}
                          </h4>
                        </div>
                        {act.place_address && (
                          <p className="text-[11px] text-slate-400 mt-1 flex items-center gap-1">
                            <span>📍</span>
                            <span>{act.place_address}</span>
                          </p>
                        )}
                        {act.custom_description && (
                          <p className="text-xs text-slate-300 mt-2 leading-relaxed">
                            {act.custom_description}
                          </p>
                        )}
                      </div>

                      {act.estimated_cost ? (
                        <div className="text-right flex-shrink-0">
                          <span className="text-[10px] text-slate-400 block">Dự trù</span>
                          <span className="text-xs font-bold text-emerald-400">
                            {act.estimated_cost.toLocaleString("vi-VN")} đ
                          </span>
                        </div>
                      ) : null}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <p className="text-center text-xs text-slate-500 py-8">
            Chưa có thông tin hoạt động cho ngày này.
          </p>
        )}
      </div>
    </div>
  );
}
