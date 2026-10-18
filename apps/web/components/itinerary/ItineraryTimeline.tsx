"use client";

import React, { useState, useEffect } from "react";
import { ItineraryDetail, ActivityDetail } from "@/hooks/useItinerary";

interface ItineraryTimelineProps {
  itinerary: ItineraryDetail;
  onEditPrompt?: (prompt: string) => void;
  onActivityEdit?: (activity: ActivityDetail) => void;
  selectedActivityId?: number | string | null;
  onActivitySelect?: (activity: ActivityDetail, dayNumber: number) => void;
  activeDayFilter?: number | "all";
  onDayFilterChange?: (day: number | "all") => void;
}

export function ItineraryTimeline({
  itinerary,
  onEditPrompt,
  onActivityEdit,
  selectedActivityId,
  onActivitySelect,
  activeDayFilter,
  onDayFilterChange,
}: ItineraryTimelineProps) {
  // Hỗ trợ cả controlled lẫn uncontrolled state cho bộ lọc ngày
  const [internalDayFilter, setInternalDayFilter] = useState<number | "all">("all");
  const currentDayFilter = activeDayFilter !== undefined ? activeDayFilter : internalDayFilter;

  const handleDaySelect = (day: number | "all") => {
    if (onDayFilterChange) {
      onDayFilterChange(day);
    } else {
      setInternalDayFilter(day);
    }
  };

  const days = itinerary?.days || [];

  // Lọc danh sách ngày cần hiển thị
  const displayedDays =
    currentDayFilter === "all"
      ? days
      : days.filter((d) => d.day_number === currentDayFilter);

  // Tự động cuộn đến hoạt động đang được chọn khi thay đổi
  useEffect(() => {
    if (selectedActivityId) {
      const el = document.getElementById(`activity-card-${selectedActivityId}`);
      if (el) {
        el.scrollIntoView({ behavior: "smooth", block: "nearest" });
      }
    }
  }, [selectedActivityId]);

  return (
    <div className="rounded-2xl bg-slate-900/80 border border-slate-800 p-5 sm:p-6 shadow-xl backdrop-blur-sm">
      {/* Overview Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-5 border-b border-slate-800 gap-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xl">🗺️</span>
            <h2 className="text-lg sm:text-xl font-bold text-slate-100">
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

      {/* Day Selector Tabs (Prompt 4 - Mục 7) */}
      <div className="flex items-center gap-2 py-3.5 border-b border-slate-800 overflow-x-auto custom-scrollbar">
        {/* Nút Tất cả các ngày */}
        <button
          type="button"
          onClick={() => handleDaySelect("all")}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap flex items-center gap-1.5 ${
            currentDayFilter === "all"
              ? "bg-gradient-to-r from-teal-500 to-cyan-500 text-slate-950 shadow-md shadow-teal-900/30 font-extrabold"
              : "bg-slate-800/80 hover:bg-slate-800 text-slate-400 hover:text-slate-200 border border-slate-700/60"
          }`}
        >
          <span>🌟</span>
          <span>Tất cả các ngày</span>
        </button>

        {/* Các ngày chi tiết */}
        {days.map((day) => {
          const isSelected = currentDayFilter === day.day_number;
          const actsWithCoords = (day.activities || []).filter(
            (a) => a.latitude != null && a.longitude != null
          ).length;

          return (
            <button
              key={day.id || day.day_number}
              type="button"
              onClick={() => handleDaySelect(day.day_number)}
              className={`px-3.5 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap flex items-center gap-1.5 ${
                isSelected
                  ? "bg-gradient-to-r from-teal-500 to-cyan-500 text-slate-950 shadow-md shadow-teal-900/30 font-extrabold"
                  : "bg-slate-800/80 hover:bg-slate-800 text-slate-400 hover:text-slate-200 border border-slate-700/60"
              }`}
            >
              <span>Ngày {day.day_number}</span>
              {actsWithCoords > 0 && (
                <span
                  className={`text-[10px] px-1.5 py-0.2 rounded-full font-bold ${
                    isSelected
                      ? "bg-slate-950/20 text-slate-950"
                      : "bg-teal-500/10 text-teal-300"
                  }`}
                  title={`${actsWithCoords} điểm có tọa độ trên bản đồ`}
                >
                  📍{actsWithCoords}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Days & Activities List */}
      <div className="pt-5 space-y-8">
        {displayedDays.length > 0 ? (
          displayedDays.map((day) => (
            <div key={day.id || day.day_number} className="space-y-4">
              <div className="flex items-center justify-between pb-1 border-b border-slate-800/60">
                <h3 className="text-sm font-bold text-teal-300 flex items-center gap-2">
                  <span className="w-6 h-6 rounded-lg bg-teal-500/10 border border-teal-500/20 flex items-center justify-center text-xs">
                    {day.day_number}
                  </span>
                  <span>
                    Ngày {day.day_number}: {day.title || day.theme || "Khám phá các điểm đến"}
                  </span>
                  {day.date && (
                    <span className="text-xs font-normal text-slate-500">
                      ({day.date})
                    </span>
                  )}
                </h3>
                {day.notes && (
                  <span className="text-[11px] text-slate-400 italic hidden sm:inline">
                    💡 {day.notes}
                  </span>
                )}
              </div>

              {/* Activities Timeline */}
              <div className="relative pl-6 space-y-4 before:absolute before:left-2 before:top-2 before:bottom-2 before:w-0.5 before:bg-gradient-to-b before:from-teal-500 before:via-cyan-500 before:to-slate-800">
                {(day.activities || []).length > 0 ? (
                  day.activities.map((act) => {
                    const hasCoordinates = act.latitude != null && act.longitude != null;
                    const isSelected = selectedActivityId === act.id;

                    return (
                      <div
                        id={`activity-card-${act.id}`}
                        key={act.id}
                        onClick={() => onActivitySelect?.(act, day.day_number)}
                        className={`relative group cursor-pointer transition-all duration-200 rounded-xl p-4 border ${
                          isSelected
                            ? "bg-teal-950/40 border-teal-400 shadow-lg shadow-teal-500/10 ring-2 ring-teal-400/50"
                            : "bg-slate-800/60 hover:bg-slate-800 border-slate-700/60 hover:border-teal-500/30 shadow-sm"
                        }`}
                      >
                        {/* Timeline bullet indicator */}
                        <div
                          className={`absolute -left-6 top-5 w-4 h-4 rounded-full border-2 flex items-center justify-center transition-transform ${
                            isSelected
                              ? "bg-teal-400 border-teal-200 scale-125"
                              : "bg-slate-900 border-teal-400 group-hover:scale-110"
                          }`}
                        >
                          <div
                            className={`w-1.5 h-1.5 rounded-full ${
                              isSelected ? "bg-slate-950" : "bg-teal-400"
                            }`}
                          />
                        </div>

                        {/* Card Header & Content */}
                        <div className="flex items-start justify-between gap-3">
                          <div className="flex-1">
                            <div className="flex flex-wrap items-center gap-2 mb-1">
                              {/* Order & Day Badge */}
                              <span
                                className={`text-[10px] font-black px-2 py-0.5 rounded-md ${
                                  isSelected
                                    ? "bg-teal-400 text-slate-950 font-black"
                                    : "bg-slate-700/80 text-teal-300"
                                }`}
                              >
                                N{day.day_number} - #{act.order_index ?? act.activity_order ?? 1}
                              </span>

                              {/* Time slot */}
                              {act.time_slot && (
                                <span className="text-[11px] font-semibold px-2 py-0.5 rounded bg-slate-700/50 text-slate-300">
                                  ⏰ {act.time_slot}
                                </span>
                              )}

                              {/* Map status indicator */}
                              {hasCoordinates ? (
                                <span className="text-[10px] text-teal-400/90 flex items-center gap-0.5 font-medium">
                                  <span>🗺️</span>
                                  <span>Xem trên bản đồ</span>
                                </span>
                              ) : (
                                <span
                                  className="text-[10px] text-amber-400/80 bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/20"
                                  title="Địa điểm này chưa gắn tọa độ GPS nên chưa thể hiển thị trên bản đồ"
                                >
                                  📍 Chưa có tọa độ
                                </span>
                              )}
                            </div>

                            <h4
                              className={`text-sm font-bold transition-colors ${
                                isSelected
                                  ? "text-teal-200 font-extrabold"
                                  : "text-slate-100 group-hover:text-teal-300"
                              }`}
                            >
                              {act.place_name || act.title}
                            </h4>

                            {act.place_address && (
                              <p className="text-[11px] text-slate-400 mt-1 flex items-start gap-1 leading-normal">
                                <span className="flex-shrink-0">📍</span>
                                <span>{act.place_address}</span>
                              </p>
                            )}

                            {act.custom_description && (
                              <p className="text-xs text-slate-300 mt-2 leading-relaxed">
                                {act.custom_description}
                              </p>
                            )}

                            {act.note && (
                              <p className="text-[11px] text-amber-300/80 mt-1.5 italic">
                                💡 Ghi chú: {act.note}
                              </p>
                            )}
                          </div>

                          <div className="flex flex-col items-end gap-2 flex-shrink-0">
                            {act.estimated_cost ? (
                              <div className="text-right">
                                <span className="text-[10px] text-slate-400 block">Dự trù</span>
                                <span className="text-xs font-bold text-emerald-400">
                                  {act.estimated_cost.toLocaleString("vi-VN")} đ
                                </span>
                              </div>
                            ) : null}
                            {onActivityEdit && (
                              <button
                                type="button"
                                onClick={(event) => {
                                  event.stopPropagation();
                                  onActivityEdit(act);
                                }}
                                className="rounded-lg border border-teal-500/30 bg-teal-500/10 px-2.5 py-1 text-[11px] font-bold text-teal-300 transition-colors hover:bg-teal-500/20"
                              >
                                Sửa
                              </button>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })
                ) : (
                  <p className="text-xs text-slate-500 py-4 italic">
                    Chưa có hoạt động nào trong ngày này.
                  </p>
                )}
              </div>
            </div>
          ))
        ) : (
          <div className="text-center py-12 text-slate-400 text-xs">
            <p className="text-2xl mb-2">🏝️</p>
            <p>Không có hoạt động nào cho ngày được chọn.</p>
          </div>
        )}
      </div>
    </div>
  );
}
