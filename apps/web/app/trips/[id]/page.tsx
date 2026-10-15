"use client";

import React, { useState, useMemo, useCallback } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useItinerary, ActivityDetail } from "@/hooks/useItinerary";
import { ItineraryTimeline } from "@/components/itinerary/ItineraryTimeline";
import { TravelMap, MapPlace, isValidCoordinate } from "@/components/map/TravelMap";

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

  // Chế độ xem: "split" (song song cả lịch trình & bản đồ), "timeline" (chỉ lịch trình), "map" (chỉ bản đồ)
  const [viewMode, setViewMode] = useState<"split" | "timeline" | "map">("split");
  // Bộ lọc theo ngày: "all" (toàn bộ chuyến đi) hoặc số thứ tự ngày (1, 2, 3...)
  const [filterDay, setFilterDay] = useState<number | "all">("all");
  // ID hoạt động đang được chọn (đồng bộ giữa danh sách và bản đồ)
  const [selectedActivityId, setSelectedActivityId] = useState<number | string | null>(null);

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

  // Trích xuất các địa điểm thuộc chuyến đi theo bộ lọc ngày để đưa lên bản đồ
  const itineraryMapPlaces: MapPlace[] = useMemo(() => {
    if (!itinerary?.days) return [];
    const list: MapPlace[] = [];

    itinerary.days.forEach((day) => {
      // Nếu đang lọc theo ngày cụ thể, chỉ lấy hoạt động của ngày đó
      if (filterDay !== "all" && day.day_number !== filterDay) {
        return;
      }

      (day.activities || []).forEach((act) => {
        // Chỉ thêm marker nếu có tọa độ hợp lệ
        if (isValidCoordinate(act.latitude, act.longitude)) {
          const orderNum = act.order_index ?? act.activity_order ?? 1;
          list.push({
            id: act.id, // Dùng ID hoạt động duy nhất để phân biệt cả khi trùng place_id
            name: act.place_name || act.title || "Địa điểm tham quan",
            description: act.custom_description || `Ngày ${day.day_number} • ${act.time_slot || ""}`,
            address: act.place_address,
            latitude: act.latitude,
            longitude: act.longitude,
            order: orderNum,
            day_number: day.day_number,
            time: act.time_slot,
            badge_label: filterDay === "all" ? `N${day.day_number}-${orderNum}` : `${orderNum}`,
          });
        }
      });
    });

    return list;
  }, [itinerary, filterDay]);

  // Đếm tổng số địa điểm có tọa độ trong toàn chuyến đi
  const totalGeoPlacesCount = useMemo(() => {
    if (!itinerary?.days) return 0;
    let count = 0;
    itinerary.days.forEach((day) => {
      (day.activities || []).forEach((act) => {
        if (isValidCoordinate(act.latitude, act.longitude)) {
          count++;
        }
      });
    });
    return count;
  }, [itinerary]);

  // Tương tác từ danh sách lịch trình đến bản đồ (Prompt 4 - Mục 6)
  const handleActivitySelect = useCallback(
    (act: ActivityDetail, dayNumber: number) => {
      setSelectedActivityId(act.id);

      // Nếu hoạt động không có tọa độ GPS, hiển thị thông báo
      if (!isValidCoordinate(act.latitude, act.longitude)) {
        setEditFeedback(`Hoạt động "${act.place_name || act.title}" chưa gắn tọa độ GPS nên chưa thể hiển thị vị trí trên bản đồ.`);
        setTimeout(() => setEditFeedback(null), 4000);
      }
    },
    []
  );

  // Tương tác từ bản đồ đến danh sách lịch trình (Prompt 4 - Mục 6)
  const handleMapPlaceSelect = useCallback(
    (place: MapPlace) => {
      setSelectedActivityId(place.id);

      // Nếu điểm thuộc ngày khác ngày đang lọc, tự động chuyển ngày để làm nổi bật card
      if (place.day_number != null && filterDay !== "all" && filterDay !== place.day_number) {
        setFilterDay(place.day_number);
      }
    },
    [filterDay]
  );

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans">
      {/* Top Header */}
      <header className="sticky top-0 z-20 flex items-center justify-between px-4 sm:px-6 py-3 bg-slate-900/80 backdrop-blur-xl border-b border-slate-800">
        <div className="flex items-center gap-3">
          <Link
            href="/trips"
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition-colors"
            title="Quay lại danh sách chuyến đi"
          >
            ←
          </Link>
          <div className="flex items-center gap-2">
            <span className="font-bold text-sm sm:text-base text-slate-200 truncate max-w-xs sm:max-w-md">
              {itinerary?.name || `Chi tiết Chuyến đi #${tripId}`}
            </span>
            {itinerary?.status && (
              <span
                className={`text-[10px] font-extrabold px-2 py-0.5 rounded uppercase tracking-wider ${
                  itinerary.status === "CONFIRMED"
                    ? "bg-emerald-500/20 text-emerald-300 border border-emerald-500/40"
                    : "bg-teal-500/10 text-teal-300 border border-teal-500/20"
                }`}
              >
                {itinerary.status}
              </span>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* Chế độ xem: Song song / Timeline / Bản đồ */}
          <div className="hidden lg:flex items-center p-0.5 rounded-xl bg-slate-800 border border-slate-700 text-xs font-semibold">
            <button
              type="button"
              onClick={() => setViewMode("split")}
              className={`px-3 py-1.5 rounded-lg transition-all ${
                viewMode === "split"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              ⚡ Song song
            </button>
            <button
              type="button"
              onClick={() => setViewMode("timeline")}
              className={`px-3 py-1.5 rounded-lg transition-all ${
                viewMode === "timeline"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              📋 Lịch trình
            </button>
            <button
              type="button"
              onClick={() => setViewMode("map")}
              className={`px-3 py-1.5 rounded-lg transition-all ${
                viewMode === "map"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              🗺️ Bản đồ
            </button>
          </div>

          {/* Switcher cho Mobile / Tablet */}
          <div className="flex lg:hidden items-center p-0.5 rounded-xl bg-slate-800 border border-slate-700 text-xs font-semibold">
            <button
              type="button"
              onClick={() => setViewMode("timeline")}
              className={`px-2.5 py-1 rounded-lg transition-all ${
                viewMode !== "map"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              📋 Lịch trình
            </button>
            <button
              type="button"
              onClick={() => setViewMode("map")}
              className={`px-2.5 py-1 rounded-lg transition-all ${
                viewMode === "map"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              🗺️ Bản đồ ({itineraryMapPlaces.length})
            </button>
          </div>

          {tripId && itinerary?.status !== "CONFIRMED" && (
            <button
              type="button"
              onClick={async () => {
                await confirmTrip(tripId);
                setEditFeedback("Đã chốt lịch trình thành công! Chúc bạn có một chuyến đi tuyệt vời!");
                setTimeout(() => setEditFeedback(null), 5000);
              }}
              className="hidden sm:inline-block px-3 py-1.5 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 text-slate-950 text-xs font-bold hover:brightness-110 active:scale-95 transition-all shadow-md cursor-pointer"
            >
              ✅ Chốt lịch trình
            </button>
          )}

          <Link
            href="/voice-guide"
            className="hidden md:flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-750 text-teal-300 text-xs font-semibold border border-slate-700 transition-colors"
          >
            <span>🎙️</span>
            <span>Mở Voice AI</span>
          </Link>
        </div>
      </header>

      {/* Main Body */}
      <main className="max-w-[1600px] mx-auto px-4 sm:px-6 py-6 space-y-6">
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
            {/* Thanh thông báo phản hồi (Feedback Toast) */}
            {editFeedback && (
              <div className="p-3.5 rounded-xl bg-teal-500/10 border border-teal-500/30 text-teal-300 text-xs font-medium flex items-center justify-between animate-in fade-in">
                <span>{editFeedback}</span>
                <button
                  type="button"
                  onClick={() => setEditFeedback(null)}
                  className="text-teal-400 hover:text-teal-200 text-sm ml-2"
                >
                  ✕
                </button>
              </div>
            )}

            {/* Layout nội dung chính */}
            {viewMode === "split" ? (
              /* 1. CHẾ ĐỘ XEM SONG SONG (SPLIT VIEW): Lịch trình bên trái, Bản đồ bên phải */
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
                {/* Cột trái: Lịch trình & Hoạt động */}
                <div className="lg:col-span-6 xl:col-span-6 space-y-6">
                  <ItineraryTimeline
                    itinerary={itinerary}
                    onEditPrompt={handleTimelinePrompt}
                    selectedActivityId={selectedActivityId}
                    onActivitySelect={handleActivitySelect}
                    activeDayFilter={filterDay}
                    onDayFilterChange={setFilterDay}
                  />
                </div>

                {/* Cột phải: Bản đồ tương tác bám theo khung nhìn (Sticky) */}
                <div className="lg:col-span-6 xl:col-span-6 sticky top-20">
                  <div className="rounded-2xl overflow-hidden border border-slate-800 bg-slate-900 shadow-2xl flex flex-col">
                    <div className="p-3.5 border-b border-slate-800 flex items-center justify-between bg-slate-900/95">
                      <div className="flex items-center gap-2">
                        <span className="text-base">🗺️</span>
                        <div>
                          <h3 className="text-xs sm:text-sm font-bold text-slate-100 flex items-center gap-1.5">
                            <span>Bản đồ Địa điểm Lịch trình</span>
                            <span className="text-[11px] text-teal-400 font-semibold">
                              ({itineraryMapPlaces.length} điểm {filterDay === "all" ? "toàn chuyến" : `Ngày ${filterDay}`})
                            </span>
                          </h3>
                        </div>
                      </div>

                      {/* Nút lọc ngày nhanh trên thanh công cụ bản đồ */}
                      <div className="flex items-center gap-1 text-[11px]">
                        <span className="text-slate-400 hidden sm:inline">Xem:</span>
                        <select
                          value={filterDay}
                          onChange={(e) => {
                            const val = e.target.value;
                            setFilterDay(val === "all" ? "all" : parseInt(val, 10));
                          }}
                          className="bg-slate-800 text-teal-300 font-semibold text-xs rounded-lg px-2 py-1 border border-slate-700 focus:outline-none"
                        >
                          <option value="all">Tất cả ngày ({totalGeoPlacesCount} điểm)</option>
                          {itinerary.days.map((d) => (
                            <option key={d.day_number} value={d.day_number}>
                              Ngày {d.day_number}
                            </option>
                          ))}
                        </select>
                      </div>
                    </div>

                    {/* Vùng hiển thị bản đồ MapLibre */}
                    <div className="h-[560px] w-full relative">
                      {itineraryMapPlaces.length > 0 ? (
                        <TravelMap
                          places={itineraryMapPlaces}
                          selectedPlaceId={selectedActivityId}
                          onPlaceSelect={handleMapPlaceSelect}
                          height="100%"
                          className="rounded-none border-0"
                        />
                      ) : (
                        <div className="h-full w-full flex flex-col items-center justify-center bg-slate-950 p-6 text-center text-slate-400 space-y-2">
                          <span className="text-3xl">🏝️</span>
                          <p className="text-xs font-semibold text-slate-300">
                            {filterDay === "all"
                              ? "Chuyến đi này chưa có địa điểm nào có tọa độ GPS để hiển thị."
                              : `Ngày ${filterDay} chưa có địa điểm nào có tọa độ trên bản đồ.`}
                          </p>
                          {filterDay !== "all" && totalGeoPlacesCount > 0 && (
                            <button
                              type="button"
                              onClick={() => setFilterDay("all")}
                              className="mt-2 px-3 py-1.5 rounded-lg bg-teal-500/10 text-teal-300 text-xs font-bold border border-teal-500/20 hover:bg-teal-500/20"
                            >
                              Xem tất cả các ngày ({totalGeoPlacesCount} điểm)
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ) : viewMode === "timeline" ? (
              /* 2. CHẾ ĐỘ XEM DÒNG THỜI GIAN TOÀN MÀN HÌNH */
              <div className="max-w-4xl mx-auto">
                <ItineraryTimeline
                  itinerary={itinerary}
                  onEditPrompt={handleTimelinePrompt}
                  selectedActivityId={selectedActivityId}
                  onActivitySelect={handleActivitySelect}
                  activeDayFilter={filterDay}
                  onDayFilterChange={setFilterDay}
                />
              </div>
            ) : (
              /* 3. CHẾ ĐỘ XEM BẢN ĐỒ TOÀN MÀN HÌNH */
              <div className="rounded-3xl overflow-hidden border border-slate-800 bg-slate-900 shadow-2xl">
                <div className="p-4 border-b border-slate-800 flex flex-wrap items-center justify-between gap-3 bg-slate-900/95">
                  <div className="flex items-center gap-2">
                    <span className="text-lg">🗺️</span>
                    <div>
                      <h3 className="text-sm font-bold text-slate-100 flex items-center gap-2">
                        <span>Bản đồ Toàn cảnh Chuyến đi</span>
                        <span className="text-xs text-teal-400 font-semibold">
                          ({itineraryMapPlaces.length} điểm hiển thị)
                        </span>
                      </h3>
                      <p className="text-xs text-slate-400">
                        Nhấn vào từng marker để mở popup và xem chi tiết hoạt động trong lịch trình
                      </p>
                    </div>
                  </div>

                  {/* Bộ lọc ngày trên toàn màn hình bản đồ */}
                  <div className="flex items-center gap-1.5 overflow-x-auto custom-scrollbar">
                    <button
                      type="button"
                      onClick={() => setFilterDay("all")}
                      className={`px-3 py-1 rounded-xl text-xs font-bold transition-all ${
                        filterDay === "all"
                          ? "bg-teal-500 text-slate-950 font-extrabold"
                          : "bg-slate-800 text-slate-400 hover:text-white border border-slate-700"
                      }`}
                    >
                      Tất cả các ngày ({totalGeoPlacesCount})
                    </button>
                    {itinerary.days.map((d) => (
                      <button
                        key={d.day_number}
                        type="button"
                        onClick={() => setFilterDay(d.day_number)}
                        className={`px-3 py-1 rounded-xl text-xs font-bold transition-all ${
                          filterDay === d.day_number
                            ? "bg-teal-500 text-slate-950 font-extrabold"
                            : "bg-slate-800 text-slate-400 hover:text-white border border-slate-700"
                        }`}
                      >
                        Ngày {d.day_number}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="h-[640px] w-full">
                  {itineraryMapPlaces.length > 0 ? (
                    <TravelMap
                      places={itineraryMapPlaces}
                      selectedPlaceId={selectedActivityId}
                      onPlaceSelect={handleMapPlaceSelect}
                      height="100%"
                      className="rounded-none border-0"
                    />
                  ) : (
                    <div className="h-full w-full flex flex-col items-center justify-center bg-slate-950 p-6 text-center text-slate-400 space-y-2">
                      <span className="text-3xl">🏝️</span>
                      <p className="text-xs font-semibold text-slate-300">
                        {filterDay === "all"
                          ? "Chuyến đi này chưa có địa điểm nào có tọa độ GPS để hiển thị."
                          : `Ngày ${filterDay} chưa có địa điểm nào có tọa độ trên bản đồ.`}
                      </p>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Conversational Edit Form */}
            <div className="p-5 rounded-2xl bg-slate-900/90 border border-slate-800 shadow-xl max-w-4xl mx-auto">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-base">✨</span>
                <h3 className="text-sm font-bold text-slate-200">
                  Chỉnh sửa lịch trình bằng Trợ lý AI
                </h3>
              </div>
              <p className="text-xs text-slate-400 mb-3">
                Bạn có thể yêu cầu đổi địa điểm, thêm quán ăn đặc sản, hoặc thay đổi nhịp độ chuyến đi bằng ngôn ngữ tự nhiên.
              </p>

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
