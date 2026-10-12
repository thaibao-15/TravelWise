"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { GeneratedItineraryData } from "@/types/chat";

interface TripCanvasProps {
  planningContext: any;
  itinerary: GeneratedItineraryData | null;
  isPlanning: boolean;
  onGenerateItinerary: () => void;
  onClearItinerary?: () => void;
  onRegenerateItinerary?: () => void;
  onSelectPrompt: (prompt: string) => void;
  onClose: () => void;
}

export function TripCanvas({
  planningContext,
  itinerary,
  isPlanning,
  onGenerateItinerary,
  onClearItinerary,
  onRegenerateItinerary,
  onSelectPrompt,
  onClose,
}: TripCanvasProps) {
  // Chế độ xem: 'checklist' (mặc định trước khi có lịch trình) hoặc 'itinerary' (khi đã tạo)
  const [viewMode, setViewMode] = useState<"checklist" | "itinerary">(
    itinerary ? "itinerary" : "checklist"
  );
  const [activeDayTab, setActiveDayTab] = useState<number>(0);

  // Tự động chuyển ngay sang tab Lịch trình khi có lịch trình được tạo hoặc cập nhật
  useEffect(() => {
    if (itinerary) {
      setViewMode("itinerary");
    }
  }, [itinerary]);

  // 1. Trích xuất 5 tiêu chí trong Checklist (Giống Layla AI)
  // Tiêu chí 1: WHERE TO (Điểm đến)
  const whereTo =
    planningContext?.trip?.destination?.city ||
    itinerary?.destination ||
    itinerary?.destination_city ||
    null;

  // Tiêu chí 2: WHERE FROM (Điểm khởi hành)
  const whereFrom =
    planningContext?.logistics?.departure_location ||
    planningContext?.departure_location ||
    null;

  // Tiêu chí 3: WHO'S COMING (Thành viên tham gia)
  const adults = planningContext?.trip?.travelers?.adults;
  const children = planningContext?.trip?.travelers?.children;
  const groupType = planningContext?.trip?.travelers?.group_type;
  const companionsTotal =
    planningContext?.trip?.companions_count ||
    planningContext?.companions?.count;
  let whoComing: string | null = null;
  if (adults != null && adults > 0) {
    whoComing = `${adults} người lớn${children ? `, ${children} trẻ em` : ""}`;
  } else if (companionsTotal != null && companionsTotal > 0) {
    whoComing = `${companionsTotal} người tham gia`;
  } else if (groupType && groupType !== "UNKNOWN") {
    whoComing =
      groupType === "SOLO"
        ? "Đi 1 mình"
        : groupType === "COUPLE"
        ? "Cặp đôi (2 người)"
        : groupType === "FAMILY"
        ? "Gia đình"
        : groupType === "FRIENDS"
        ? "Nhóm bạn thân"
        : groupType;
  }

  // Tiêu chí 4: WHEN YOU'D GO (Thời gian & Số ngày)
  const durationDays =
    planningContext?.trip?.dates?.duration_days ||
    planningContext?.trip?.duration_days ||
    itinerary?.duration_days ||
    null;
  const startDate = planningContext?.trip?.dates?.start_date;
  let whenGo: string | null = null;
  if (durationDays != null && durationDays > 0) {
    whenGo = `${durationDays} ngày ${durationDays > 1 ? `${durationDays - 1} đêm` : ""}`;
    if (startDate) {
      whenGo = `${whenGo} (Từ ${startDate})`;
    }
  } else if (startDate) {
    whenGo = `Khởi hành: ${startDate}`;
  }

  // Tiêu chí 5: WHAT YOU'RE AFTER (Sở thích & Phong cách)
  const interestsList =
    planningContext?.preferences?.interests ||
    planningContext?.interests ||
    [];
  const travelStyle = planningContext?.preferences?.travel_style || [];
  let whatAfter: string | null = null;
  if (interestsList.length > 0) {
    whatAfter = interestsList.slice(0, 3).join(", ");
  } else if (travelStyle.length > 0) {
    whatAfter = travelStyle.slice(0, 2).join(", ");
  }

  // Tiêu chí 6: BUDGET (Ngân sách dự kiến)
  const budgetVal =
    planningContext?.budget?.total ||
    planningContext?.trip?.budget?.total_amount ||
    planningContext?.trip?.budget?.total ||
    planningContext?.trip?.budget?.total_budget;
  let budgetText: string | null = null;
  if (budgetVal) {
    if (typeof budgetVal === "number") {
      budgetText = `${budgetVal.toLocaleString("vi-VN")} đ`;
    } else {
      budgetText = String(budgetVal);
    }
  }

  // Tiêu chí 7: TRANSPORT (Phương tiện di chuyển)
  const transportPreferred =
    planningContext?.preferences?.transport?.preferred ||
    planningContext?.logistics?.transport_mode ||
    planningContext?.trip?.preferences?.transport?.preferred ||
    [];
  let transportText: string | null = null;
  if (Array.isArray(transportPreferred) && transportPreferred.length > 0) {
    transportText = transportPreferred.join(", ");
  } else if (typeof transportPreferred === "string" && transportPreferred) {
    transportText = transportPreferred;
  }

  // Tiêu chí 8: ACCOMMODATION (Lưu trú & Nghỉ dưỡng)
  const accommPreferred =
    planningContext?.preferences?.accommodation?.type_preferred ||
    planningContext?.trip?.preferences?.accommodation?.type_preferred ||
    planningContext?.accommodation ||
    [];
  let accommText: string | null = null;
  if (Array.isArray(accommPreferred) && accommPreferred.length > 0) {
    accommText = accommPreferred.join(", ");
  } else if (typeof accommPreferred === "string" && accommPreferred) {
    accommText = accommPreferred;
  }

  // Tiêu chí 9: MUST-VISIT (Điểm nhất định phải đến)
  const mustVisitList =
    planningContext?.places?.must_visit ||
    planningContext?.trip?.places?.must_visit ||
    [];
  let mustVisitText: string | null = null;
  if (Array.isArray(mustVisitList) && mustVisitList.length > 0) {
    mustVisitText = mustVisitList
      .map((p: any) => (typeof p === "string" ? p : p.name))
      .filter(Boolean)
      .slice(0, 3)
      .join(", ");
  }

  // Danh sách các tiêu chí trong Checklist chuyến đi
  const checklistItems = [
    {
      id: "where_to",
      icon: "📍",
      title: "ĐIỂM ĐẾN",
      label: "Điểm đến",
      emptyDesc: "Để mình gợi ý nếu bạn chưa chọn điểm đến",
      value: whereTo,
      suggestPrompt: "Mình muốn đi du lịch Đà Nẵng",
    },
    {
      id: "where_from",
      icon: "🛫",
      title: "KHỞI HÀNH TỪ",
      label: "Khởi hành từ",
      emptyDesc: "Mình sẽ hỏi điểm bạn xuất phát đi",
      value: whereFrom,
      suggestPrompt: "Mình xuất phát từ Hà Nội",
    },
    {
      id: "who_coming",
      icon: "👥",
      title: "THÀNH VIÊN",
      label: "Thành viên",
      emptyDesc: "Mình sẽ hỏi bạn đi cùng những ai",
      value: whoComing,
      suggestPrompt: "Chuyến đi này có 2 người lớn",
    },
    {
      id: "when_go",
      icon: "📅",
      title: "THỜI GIAN",
      label: "Thời gian",
      emptyDesc: "Mình sẽ hỏi thời gian bạn muốn đi",
      value: whenGo,
      suggestPrompt: "Mình dự định đi 3 ngày 2 đêm",
    },
    {
      id: "what_after",
      icon: "🤍",
      title: "SỞ THÍCH & PHONG CÁCH",
      label: "Sở thích & Phong cách",
      emptyDesc: "Điều gì làm nên chuyến đi lý tưởng của bạn",
      value: whatAfter,
      suggestPrompt: "Mình thích tắm biển, cafe chill và ăn hải sản",
    },
    {
      id: "budget",
      icon: "💰",
      title: "NGÂN SÁCH DỰ KIẾN",
      label: "Ngân sách",
      emptyDesc: "Ước tính mức chi tiêu bạn mong muốn",
      value: budgetText,
      suggestPrompt: "Ngân sách của mình khoảng 4 triệu mỗi người",
    },
    {
      id: "transport",
      icon: "🛵",
      title: "PHƯƠNG TIỆN DI CHUYỂN",
      label: "Phương tiện",
      emptyDesc: "Xe máy, ô tô tự lái, máy bay hay Grab",
      value: transportText,
      suggestPrompt: "Bọn mình muốn thuê xe máy để vi vu tự do",
    },
    {
      id: "accommodation",
      icon: "🏨",
      title: "LƯU TRÚ & NGHỈ DƯỠNG",
      label: "Lưu trú",
      emptyDesc: "Khách sạn 3-4 sao, resort hay homestay",
      value: accommText,
      suggestPrompt: "Mình thích ở khách sạn 3-4 sao gần biển",
    },
    {
      id: "must_visit",
      icon: "⭐",
      title: "ĐIỂM NHẤT ĐỊNH PHẢI ĐẾN",
      label: "Điểm bắt buộc",
      emptyDesc: "Địa danh cụ thể bạn nhất định phải ghé qua",
      value: mustVisitText,
      suggestPrompt: "Lịch trình nhất định phải có Bà Nà Hills và Chùa Linh Ứng",
    },
  ];

  const totalCriteria = checklistItems.length;
  const capturedCount = checklistItems.filter((item) => Boolean(item.value)).length;
  const isReadyToGenerate = capturedCount >= 2 && Boolean(whereTo);

  const days = itinerary?.days || [];
  const activeDay = days[activeDayTab] || days[0];

  return (
    <aside className="w-[420px] lg:w-[460px] xl:w-[500px] 2xl:w-[540px] h-full flex flex-col bg-slate-900/95 border-l border-slate-800 backdrop-blur-xl shadow-2xl overflow-hidden font-sans flex-shrink-0 transition-all duration-300">
      {/* Canvas Header */}
      <div className="flex items-center justify-between px-4 py-3.5 border-b border-slate-800 bg-slate-900/80">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-tr from-teal-500 to-cyan-400 flex items-center justify-center text-slate-950 font-black text-xs shadow-md shadow-teal-500/20">
            ✨
          </div>
          <div>
            <h2 className="text-xs font-bold text-slate-100 tracking-wide">
              Kế hoạch chuyến đi
            </h2>
            <p className="text-[10px] text-teal-400 font-medium">
              Tiêu chí thu thập & Lịch trình chi tiết
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={onClose}
          className="p-1 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition-colors cursor-pointer text-xs"
          title="Đóng bảng kế hoạch"
        >
          ✕
        </button>
      </div>

      {/* Chuyển đổi giữa Tiêu chí và Lịch trình khi đã tạo */}
      {itinerary && (
        <div className="px-4 pt-3 pb-1 border-b border-slate-800 bg-slate-950/40 flex items-center gap-2">
          <button
            type="button"
            onClick={() => setViewMode("checklist")}
            className={`flex-1 py-1.5 px-2 rounded-lg text-[11px] font-bold transition-all cursor-pointer ${
              viewMode === "checklist"
                ? "bg-teal-500/20 text-teal-300 border border-teal-500/40 shadow-sm"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            📋 Tiêu chí ({capturedCount}/{totalCriteria})
          </button>
          <button
            type="button"
            onClick={() => setViewMode("itinerary")}
            className={`flex-1 py-1.5 px-2 rounded-lg text-[11px] font-bold transition-all cursor-pointer ${
              viewMode === "itinerary"
                ? "bg-teal-500 text-slate-950 shadow-md font-extrabold"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            🗓️ Lịch trình chi tiết
          </button>
        </div>
      )}

      {/* Main Content Body */}
      <div className="flex-1 overflow-y-auto custom-scrollbar p-4 space-y-4">
        {/* VIEW 1: TIÊU CHÍ CHUYẾN ĐI (Giao diện chuẩn Layla AI) */}
        {viewMode === "checklist" && (
          <div className="space-y-5 animate-in fade-in">
            {/* Vòng tròn tiến độ & Tiêu đề Checklist */}
            <div className="flex items-center gap-3.5 p-3 rounded-2xl bg-gradient-to-br from-slate-850 to-slate-900 border border-slate-800 shadow-inner">
              <div className="relative w-12 h-12 flex-shrink-0 flex items-center justify-center">
                <svg className="w-12 h-12 -rotate-90" viewBox="0 0 36 36">
                  <path
                    className="text-slate-800"
                    strokeWidth="3.2"
                    stroke="currentColor"
                    fill="none"
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  />
                  <path
                    className="text-teal-400 transition-all duration-700 ease-out"
                    strokeDasharray={`${(capturedCount / totalCriteria) * 100}, 100`}
                    strokeWidth="3.2"
                    strokeLinecap="round"
                    stroke="currentColor"
                    fill="none"
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  />
                </svg>
                <span className="absolute font-black text-xs text-slate-100">
                  {capturedCount}/{totalCriteria}
                </span>
              </div>

              <div>
                <span className="text-[10px] font-extrabold uppercase tracking-wider text-teal-400 block">
                  TIÊU CHÍ CHUYẾN ĐI
                </span>
                <h3 className="text-sm font-bold text-slate-100 leading-snug">
                  Kế hoạch chuyến đi của bạn
                </h3>
                <p className="text-[11px] text-slate-400">
                  Đã thu thập {capturedCount}/{totalCriteria} tiêu chí
                </p>
              </div>
            </div>

            {/* Danh sách 5 tiêu chí xếp dọc có đường line kết nối */}
            <div className="relative pl-6 space-y-5 before:absolute before:left-2.5 before:top-3 before:bottom-3 before:w-0.5 before:bg-slate-800">
              {checklistItems.map((item, index) => {
                const isCaptured = Boolean(item.value);
                return (
                  <div key={item.id} className="relative group">
                    {/* Nút chỉ báo tròn (Tick xanh khi đã có, dấu chấm xám khi chưa có) */}
                    <div
                      className={`absolute -left-6 top-0.5 w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-black transition-all ${
                        isCaptured
                          ? "bg-teal-400 text-slate-950 ring-4 ring-slate-900 shadow-md shadow-teal-500/30"
                          : "bg-slate-800 text-slate-500 border border-slate-700 ring-4 ring-slate-900"
                      }`}
                    >
                      {isCaptured ? "✓" : index + 1}
                    </div>

                    {/* Tiêu đề & Nội dung từng tiêu chí */}
                    <div>
                      <div className="flex items-center gap-1.5 text-[11px] font-bold text-slate-300 uppercase tracking-wide">
                        <span>{item.icon}</span>
                        <span>{item.title}</span>
                      </div>

                      {isCaptured ? (
                        <div className="mt-1 p-2 rounded-xl bg-teal-950/40 border border-teal-500/30 text-teal-200 text-xs font-semibold shadow-sm flex items-center justify-between">
                          <span>{item.value}</span>
                          <span className="text-[10px] text-teal-400 font-bold bg-teal-500/10 px-1.5 py-0.5 rounded">
                            Đã ghi nhận
                          </span>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={() => onSelectPrompt(item.suggestPrompt)}
                          className="mt-1 text-left w-full text-xs text-slate-400 hover:text-teal-300 leading-relaxed transition-colors cursor-pointer block group/btn"
                        >
                          <span className="text-[11px] text-slate-400 group-hover/btn:text-teal-300 flex items-center justify-between">
                            <span>{item.emptyDesc}</span>
                            <span className="text-teal-400 font-bold ml-1">→</span>
                          </span>
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Action Nút lớn: Tạo lịch trình */}
            <div className="pt-2 border-t border-slate-800 space-y-2">
              <button
                type="button"
                onClick={onGenerateItinerary}
                disabled={isPlanning || !isReadyToGenerate}
                className={`w-full py-3 px-4 rounded-xl font-bold text-xs shadow-lg transition-all flex items-center justify-center gap-2 cursor-pointer ${
                  isReadyToGenerate
                    ? "bg-gradient-to-r from-teal-400 via-cyan-400 to-teal-300 text-slate-950 hover:brightness-110 active:scale-[0.98] shadow-teal-500/25"
                    : "bg-slate-800/80 text-slate-500 cursor-not-allowed border border-slate-700/60"
                }`}
              >
                {isPlanning ? (
                  <>
                    <span className="w-3.5 h-3.5 border-2 border-slate-950 border-t-transparent rounded-full animate-spin" />
                    <span>✨ Đang tạo lịch trình...</span>
                  </>
                ) : (
                  <>
                    <span>✨ Tạo lịch trình ngay</span>
                  </>
                )}
              </button>

              <p className="text-[10px] text-slate-400 text-center leading-relaxed px-1">
                TravelWise sẽ tạo lịch trình ngay và tự động bổ sung thông tin còn thiếu — hoặc tiếp tục trò chuyện để hoàn thiện trọn vẹn {totalCriteria} tiêu chí.
              </p>
            </div>
          </div>
        )}

        {/* VIEW 2: LỊCH TRÌNH CHI TIẾT (Hiển thị ngay khi được tạo) */}
        {viewMode === "itinerary" && itinerary && (
          <div className="space-y-3.5 animate-in fade-in">
            {/* Header tóm tắt chuyến đi */}
            <div className="p-3.5 rounded-2xl bg-gradient-to-br from-teal-950/60 via-slate-850 to-slate-900 border border-teal-500/40 shadow-lg space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-extrabold uppercase tracking-wider text-teal-400 bg-teal-500/10 px-2 py-0.5 rounded-md border border-teal-500/20">
                  🎉 LỊCH TRÌNH ĐÃ TẠO
                </span>
                {itinerary.trip_id ? (
                  <Link
                    href={`/trips/${itinerary.trip_id}`}
                    className="text-[10px] px-2.5 py-1 rounded-lg bg-teal-500 text-slate-950 hover:bg-teal-400 font-extrabold transition-colors flex items-center gap-1 shadow-sm"
                  >
                    Xem chi tiết &rarr;
                  </Link>
                ) : (
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-300 border border-emerald-500/20 font-bold">
                    Hoàn thành
                  </span>
                )}
              </div>

              <div>
                <h3 className="text-sm font-bold text-slate-100 leading-snug">
                  {itinerary.name || `Khám phá ${itinerary.destination || "chuyến đi"}`}
                </h3>
                <div className="flex flex-wrap items-center gap-2 text-[11px] text-slate-300 mt-1">
                  <span>📍 {itinerary.destination || itinerary.destination_city || "Điểm đến"}</span>
                  <span>•</span>
                  <span>📅 {days.length} Ngày ({itinerary.total_activities || days.length * 3} hoạt động)</span>
                  {itinerary.estimated_total_cost ? (
                    <>
                      <span>•</span>
                      <span className="text-emerald-400 font-semibold">
                        💰 {itinerary.estimated_total_cost.toLocaleString("vi-VN")} đ
                      </span>
                    </>
                  ) : null}
                </div>
              </div>

              {/* Hàng nút tác vụ: Tạo lại lịch trình khác & Xóa lịch trình */}
              <div className="flex items-center gap-2 pt-2 border-t border-slate-800/80">
                <button
                  type="button"
                  onClick={() => {
                    if (onRegenerateItinerary) {
                      onRegenerateItinerary();
                    } else {
                      onGenerateItinerary();
                    }
                  }}
                  disabled={isPlanning}
                  className="flex-1 py-1.5 px-3 rounded-xl bg-teal-500/15 hover:bg-teal-500/25 border border-teal-500/35 text-teal-300 text-xs font-bold transition-all flex items-center justify-center gap-1.5 cursor-pointer disabled:opacity-50 active:scale-95 shadow-sm"
                  title="Làm mới và tạo lại một lịch trình khác với các gợi ý mới mẻ hơn"
                >
                  <span>🔄</span>
                  <span>Tạo lại lịch trình khác</span>
                </button>

                {onClearItinerary && (
                  <button
                    type="button"
                    onClick={() => {
                      onClearItinerary();
                      setViewMode("checklist");
                    }}
                    disabled={isPlanning}
                    className="py-1.5 px-3 rounded-xl bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 text-rose-300 hover:text-rose-200 text-xs font-bold transition-all flex items-center gap-1 cursor-pointer disabled:opacity-50 active:scale-95 shadow-sm"
                    title="Xóa lịch trình hiện tại và quay về danh sách tiêu chí"
                  >
                    <span>🗑️</span>
                    <span>Xóa</span>
                  </button>
                )}
              </div>
            </div>

            {/* Day Selector Tabs */}
            {days.length > 1 && (
              <div className="flex gap-1.5 overflow-x-auto custom-scrollbar pb-1">
                {days.map((day, idx) => (
                  <button
                    key={idx}
                    type="button"
                    onClick={() => setActiveDayTab(idx)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer whitespace-nowrap ${
                      activeDayTab === idx
                        ? "bg-teal-500 text-slate-950 shadow-md font-extrabold"
                        : "bg-slate-800 text-slate-400 hover:text-slate-200 border border-slate-700/50"
                    }`}
                  >
                    Ngày {day.day_number || idx + 1}
                  </button>
                ))}
              </div>
            )}

            {/* Active Day Activities */}
            {activeDay && (
              <div className="space-y-3 pt-1">
                <div className="p-3 rounded-2xl bg-slate-850/90 border border-slate-800 text-xs shadow-inner">
                  <div className="font-bold text-teal-300 flex items-center justify-between">
                    <span className="text-sm">{activeDay.title || `Khám phá Ngày ${activeDay.day_number}`}</span>
                    <span className="text-[10px] text-slate-400 font-mono bg-slate-800 px-2 py-0.5 rounded-full border border-slate-700">
                      {activeDay.activities?.length || 0} hoạt động
                    </span>
                  </div>
                  {activeDay.description && (
                    <p className="text-[11px] text-slate-300 mt-1.5 leading-relaxed">
                      {activeDay.description}
                    </p>
                  )}
                </div>

                {/* Timeline danh sách các hoạt động chi tiết */}
                <div className="relative pl-5 space-y-3.5 before:absolute before:left-2 before:top-2 before:bottom-2 before:w-0.5 before:bg-gradient-to-b before:from-teal-400 before:via-cyan-500 before:to-slate-800">
                  {(activeDay.activities || []).map((act, idx) => {
                    const placeName = act.place?.name || act.title;
                    const address = act.place?.address;
                    const timeSlot = act.start_time
                      ? act.end_time
                        ? `${act.start_time} - ${act.end_time}`
                        : act.start_time
                      : null;
                    const desc = act.description || act.note;
                    const actType = act.activity_type || "VISIT";

                    // Badge loại hoạt động
                    const typeBadge =
                      actType === "MEAL"
                        ? { label: "Ẩm thực & Đặc sản", icon: "🍜", color: "text-amber-300 bg-amber-500/10 border-amber-500/30" }
                        : actType === "LODGING"
                        ? { label: "Nghỉ ngơi / Khách sạn", icon: "🏨", color: "text-purple-300 bg-purple-500/10 border-purple-500/30" }
                        : actType === "TRANSPORT"
                        ? { label: "Di chuyển", icon: "🚗", color: "text-blue-300 bg-blue-500/10 border-blue-500/30" }
                        : { label: "Tham quan & Trải nghiệm", icon: "🏛️", color: "text-teal-300 bg-teal-500/10 border-teal-500/30" };

                    return (
                      <div
                        key={idx}
                        className="relative p-3.5 rounded-2xl bg-slate-850/90 border border-slate-800 hover:border-teal-500/40 hover:bg-slate-800/90 transition-all text-xs space-y-2 group shadow-sm"
                      >
                        {/* Dot trên timeline */}
                        <div className="absolute -left-5 top-3.5 w-3.5 h-3.5 rounded-full bg-slate-900 border-2 border-teal-400 flex items-center justify-center shadow-sm">
                          <div className="w-1.5 h-1.5 rounded-full bg-teal-400" />
                        </div>

                        {/* Hàng trên: Loại hoạt động & Khung giờ */}
                        <div className="flex items-center justify-between gap-2 flex-wrap">
                          <span
                            className={`text-[10px] font-bold px-2 py-0.5 rounded-md border flex items-center gap-1 ${typeBadge.color}`}
                          >
                            <span>{typeBadge.icon}</span>
                            <span>{typeBadge.label}</span>
                          </span>

                          {timeSlot && (
                            <span className="text-[10px] text-teal-300 font-mono font-bold bg-slate-900/90 px-2 py-0.5 rounded-md border border-slate-700/60 flex items-center gap-1 shadow-inner">
                              <span>⏰</span>
                              <span>{timeSlot}</span>
                              {act.duration_minutes ? (
                                <span className="text-slate-400 font-normal">
                                  ({act.duration_minutes}p)
                                </span>
                              ) : null}
                            </span>
                          )}
                        </div>

                        {/* Tên địa điểm / Tiêu đề */}
                        <div>
                          <h4 className="font-bold text-slate-100 text-sm leading-snug group-hover:text-teal-300 transition-colors">
                            {placeName}
                          </h4>
                          {address && (
                            <p className="text-[11px] text-slate-400 flex items-start gap-1 mt-1">
                              <span className="flex-shrink-0 mt-0.5">📍</span>
                              <span className="line-clamp-2">{address}</span>
                            </p>
                          )}
                        </div>

                        {/* Mô tả chi tiết hoạt động */}
                        {desc && (
                          <div className="p-2.5 rounded-xl bg-slate-900/70 border border-slate-800 text-[11px] text-slate-300 leading-relaxed">
                            {desc}
                          </div>
                        )}

                        {/* Chi phí & Nút hành động nhanh */}
                        <div className="flex items-center justify-between pt-1 border-t border-slate-800/80 text-[11px]">
                          {act.estimated_cost ? (
                            <span className="text-emerald-400 font-bold flex items-center gap-1">
                              <span>💰 Vé/Chi phí:</span>
                              <span>{act.estimated_cost.toLocaleString("vi-VN")} đ</span>
                            </span>
                          ) : (
                            <span className="text-slate-400 text-[10px]">
                              Miễn phí vé / Tự túc
                            </span>
                          )}

                          <button
                            type="button"
                            onClick={() =>
                              onSelectPrompt(`Mình muốn đổi hoặc thay thế điểm '${placeName}' ở Ngày ${activeDay.day_number} sang một địa điểm khác`)
                            }
                            className="text-[10px] text-slate-400 hover:text-teal-300 font-semibold px-2 py-0.5 rounded bg-slate-800 hover:bg-slate-700 border border-slate-700/60 transition-colors cursor-pointer"
                            title="Yêu cầu AI đổi địa điểm này"
                          >
                            Đổi điểm này ↺
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Quick Edit Suggestions */}
        <div className="pt-3 border-t border-slate-800/80">
          <span className="text-[10px] font-bold text-slate-400 block mb-2">
            Gợi ý trao đổi cùng AI Tour Guide
          </span>
          <div className="flex flex-col gap-1.5">
            {[
              "🌊 Đổi sang lịch trình đi biển và ngắm hoàng hôn",
              "🍜 Thêm các quán ăn đặc sản nổi tiếng",
              "☕ Tìm quán cafe view đẹp chill buổi tối",
            ].map((prompt, i) => (
              <button
                key={i}
                type="button"
                onClick={() => onSelectPrompt(prompt)}
                className="text-left p-2 rounded-xl bg-slate-850 hover:bg-slate-800 border border-slate-800 hover:border-teal-500/30 text-[11px] text-slate-300 transition-all cursor-pointer"
              >
                {prompt}
              </button>
            ))}
          </div>
        </div>
      </div>
    </aside>
  );
}
