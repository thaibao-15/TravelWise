"use client";

import React, { useState, useMemo, useCallback } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useItinerary, ActivityDetail, ActivityUpdatePayload } from "@/hooks/useItinerary";
import { ItineraryTimeline } from "@/components/itinerary/ItineraryTimeline";
import { TravelMap, MapPlace, isValidCoordinate } from "@/components/map/TravelMap";
import { apiFetch } from "@/services/api";

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
    updateActivity,
    confirmTrip,
    refreshItinerary,
  } = useItinerary(tripId);

  // Chế độ xem: "split" (song song cả lịch trình & bản đồ), "timeline" (chỉ lịch trình), "map" (chỉ bản đồ)
  const [viewMode, setViewMode] = useState<"split" | "timeline" | "map">("split");
  // Bộ lọc theo ngày: "all" (toàn bộ chuyến đi) hoặc số thứ tự ngày (1, 2, 3...)
  const [filterDay, setFilterDay] = useState<number | "all">("all");
  // ID hoạt động đang được chọn (đồng bộ giữa danh sách và bản đồ)
  const [selectedActivityId, setSelectedActivityId] = useState<number | string | null>(null);

  const [editPrompt, setEditPrompt] = useState("");
  const [editFeedback, setEditFeedback] = useState<string | null>(null);
  const [isMetadataEditing, setIsMetadataEditing] = useState(false);
  const [metadataForm, setMetadataForm] = useState({
    name: "",
    destination_city: "",
    destination_country: "",
    start_date: "",
    end_date: "",
  });
  const [isSavingMetadata, setIsSavingMetadata] = useState(false);
  const [editingActivity, setEditingActivity] = useState<ActivityDetail | null>(null);
  const [activityForm, setActivityForm] = useState({
    title: "",
    description: "",
    start_time: "",
    end_time: "",
    duration_minutes: "",
    estimated_cost: "",
    note: "",
  });
  const [isSavingActivity, setIsSavingActivity] = useState(false);

  const startMetadataEdit = () => {
    if (!itinerary) return;
    setMetadataForm({
      name: itinerary.name || "",
      destination_city: itinerary.destination_city || "",
      destination_country: itinerary.destination_country || "",
      start_date: itinerary.start_date || "",
      end_date: itinerary.end_date || "",
    });
    setIsMetadataEditing(true);
  };

  const saveMetadata = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!tripId || !metadataForm.destination_city.trim()) return;
    setIsSavingMetadata(true);
    try {
      await apiFetch(`/api/v1/trips/${tripId}`, {
        method: "PATCH",
        body: JSON.stringify({
          ...metadataForm,
          name: metadataForm.name.trim() || undefined,
          destination_city: metadataForm.destination_city.trim(),
          destination_country: metadataForm.destination_country.trim() || undefined,
          start_date: metadataForm.start_date || undefined,
          end_date: metadataForm.end_date || undefined,
        }),
      });
      await refreshItinerary();
      setIsMetadataEditing(false);
      setEditFeedback("Đã cập nhật thông tin chuyến đi.");
    } catch (err) {
      setEditFeedback(err instanceof Error ? err.message : "Không thể cập nhật chuyến đi.");
    } finally {
      setIsSavingMetadata(false);
    }
  };

  const startActivityEdit = (activity: ActivityDetail) => {
    setEditingActivity(activity);
    setActivityForm({
      title: activity.title || activity.place_name || "",
      description: activity.description || activity.custom_description || "",
      start_time: activity.start_time || "",
      end_time: activity.end_time || "",
      duration_minutes: activity.duration_minutes?.toString() || "",
      estimated_cost: activity.estimated_cost?.toString() || "",
      note: activity.note || "",
    });
  };

  const saveActivity = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingActivity || !activityForm.title.trim() || isSavingActivity) return;

    const payload: ActivityUpdatePayload = {
      title: activityForm.title.trim(),
      description: activityForm.description.trim() || null,
      start_time: activityForm.start_time || null,
      end_time: activityForm.end_time || null,
      duration_minutes: activityForm.duration_minutes
        ? Number(activityForm.duration_minutes)
        : null,
      estimated_cost: activityForm.estimated_cost ? Number(activityForm.estimated_cost) : null,
      note: activityForm.note.trim() || null,
    };

    setIsSavingActivity(true);
    try {
      await updateActivity(editingActivity.id, payload);
      setEditingActivity(null);
      setEditFeedback("Đã cập nhật hoạt động.");
      setTimeout(() => setEditFeedback(null), 4000);
    } catch {
      // The hook exposes the API error through the page's existing error state.
    } finally {
      setIsSavingActivity(false);
    }
  };

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

      // Thứ tự marker phải bắt đầu lại từ 1 cho từng ngày, không dùng
      // order_index toàn itinerary vì giá trị đó có thể bị nhảy giữa các ngày.
      let dayMapOrder = 0;
      (day.activities || []).forEach((act) => {
        // Chỉ thêm marker nếu có tọa độ hợp lệ
        if (isValidCoordinate(act.latitude, act.longitude)) {
          dayMapOrder += 1;
          list.push({
            id: act.id, // Dùng ID hoạt động duy nhất để phân biệt cả khi trùng place_id
            name: act.place_name || act.title || "Địa điểm tham quan",
            description: act.custom_description || `Ngày ${day.day_number} • ${act.time_slot || ""}`,
            address: act.place_address,
            latitude: act.latitude,
            longitude: act.longitude,
            image_url: act.image_url ?? act.place?.image_url,
            order: dayMapOrder,
            day_number: day.day_number,
            time: act.time_slot,
            badge_label:
              filterDay === "all"
                ? `N${day.day_number}-${dayMapOrder}`
                : `${dayMapOrder}`,
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
          <button
            type="button"
            onClick={startMetadataEdit}
            className="hidden sm:inline-block px-3 py-1.5 rounded-xl bg-slate-800 text-slate-200 text-xs font-semibold border border-slate-700 hover:border-teal-500/50 transition-colors"
          >
            ✏️ Sửa thông tin
          </button>
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

            {isMetadataEditing && (
              <form onSubmit={saveMetadata} className="p-5 rounded-2xl bg-slate-900 border border-teal-500/30 shadow-xl">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-sm font-bold text-slate-200">Cập nhật thông tin chuyến đi</h3>
                  <button type="button" onClick={() => setIsMetadataEditing(false)} className="text-slate-400 hover:text-white">✕</button>
                </div>
                <div className="grid sm:grid-cols-2 gap-3">
                  {([
                    ["name", "Tên chuyến đi"],
                    ["destination_city", "Thành phố"],
                    ["destination_country", "Quốc gia"],
                    ["start_date", "Ngày bắt đầu"],
                    ["end_date", "Ngày kết thúc"],
                  ] as const).map(([field, label]) => (
                    <label key={field} className="text-xs font-semibold text-slate-300">
                      {label}
                      <input
                        type={field.includes("date") ? "date" : "text"}
                        value={metadataForm[field]}
                        onChange={(e) => setMetadataForm((current) => ({ ...current, [field]: e.target.value }))}
                        className="mt-1 w-full rounded-lg bg-slate-800 border border-slate-700 px-3 py-2 text-xs text-slate-100"
                      />
                    </label>
                  ))}
                </div>
                <div className="flex justify-end gap-2 mt-4">
                  <button type="button" onClick={() => setIsMetadataEditing(false)} className="px-3 py-2 rounded-lg text-xs text-slate-300 bg-slate-800">Hủy</button>
                  <button type="submit" disabled={isSavingMetadata} className="px-4 py-2 rounded-lg text-xs font-bold bg-teal-500 text-slate-950 disabled:opacity-50">
                    {isSavingMetadata ? "Đang lưu..." : "Lưu thay đổi"}
                  </button>
                </div>
              </form>
            )}

            {editingActivity && (
              <form
                onSubmit={saveActivity}
                className="mb-6 rounded-2xl border border-teal-500/30 bg-slate-900/80 p-5 shadow-xl"
              >
                <div className="flex items-center justify-between gap-3 mb-4">
                  <div>
                    <h2 className="text-sm font-bold text-slate-100">Sửa hoạt động</h2>
                    <p className="text-xs text-slate-400 mt-1">
                      Cập nhật riêng hoạt động “{editingActivity.place_name || editingActivity.title}”.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setEditingActivity(null)}
                    className="text-slate-400 hover:text-slate-200 text-lg"
                    aria-label="Đóng form sửa hoạt động"
                  >
                    ×
                  </button>
                </div>
                <div className="grid sm:grid-cols-2 gap-3">
                  <label className="text-xs font-semibold text-slate-300 sm:col-span-2">
                    Tên hoạt động
                    <input
                      required
                      value={activityForm.title}
                      onChange={(e) => setActivityForm((current) => ({ ...current, title: e.target.value }))}
                      className="mt-1 w-full rounded-lg bg-slate-800 border border-slate-700 px-3 py-2 text-xs text-slate-100"
                    />
                  </label>
                  {([
                    ["start_time", "Bắt đầu", "time"],
                    ["end_time", "Kết thúc", "time"],
                    ["duration_minutes", "Thời lượng (phút)", "number"],
                    ["estimated_cost", "Chi phí dự kiến", "number"],
                  ] as const).map(([field, label, type]) => (
                    <label key={field} className="text-xs font-semibold text-slate-300">
                      {label}
                      <input
                        type={type}
                        min={type === "number" ? 0 : undefined}
                        value={activityForm[field]}
                        onChange={(e) => setActivityForm((current) => ({ ...current, [field]: e.target.value }))}
                        className="mt-1 w-full rounded-lg bg-slate-800 border border-slate-700 px-3 py-2 text-xs text-slate-100"
                      />
                    </label>
                  ))}
                  <label className="text-xs font-semibold text-slate-300 sm:col-span-2">
                    Mô tả
                    <textarea
                      rows={2}
                      value={activityForm.description}
                      onChange={(e) => setActivityForm((current) => ({ ...current, description: e.target.value }))}
                      className="mt-1 w-full rounded-lg bg-slate-800 border border-slate-700 px-3 py-2 text-xs text-slate-100"
                    />
                  </label>
                  <label className="text-xs font-semibold text-slate-300 sm:col-span-2">
                    Ghi chú
                    <textarea
                      rows={2}
                      value={activityForm.note}
                      onChange={(e) => setActivityForm((current) => ({ ...current, note: e.target.value }))}
                      className="mt-1 w-full rounded-lg bg-slate-800 border border-slate-700 px-3 py-2 text-xs text-slate-100"
                    />
                  </label>
                </div>
                <div className="flex justify-end gap-2 mt-4">
                  <button type="button" onClick={() => setEditingActivity(null)} className="px-3 py-2 rounded-lg text-xs text-slate-300 bg-slate-800">
                    Hủy
                  </button>
                  <button type="submit" disabled={isSavingActivity} className="px-4 py-2 rounded-lg text-xs font-bold bg-teal-500 text-slate-950 disabled:opacity-50">
                    {isSavingActivity ? "Đang lưu..." : "Lưu hoạt động"}
                  </button>
                </div>
              </form>
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
                    onActivityEdit={startActivityEdit}
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
                  onActivityEdit={startActivityEdit}
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
