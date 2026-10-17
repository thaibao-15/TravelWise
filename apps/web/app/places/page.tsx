"use client";

import React, { useState, useEffect, useMemo } from "react";
import Link from "next/link";
import { placeService, PlaceItem } from "@/services/place.service";
import { TravelMap, MapPlace } from "@/components/map/TravelMap";

export default function PlacesPage() {
  const [places, setPlaces] = useState<PlaceItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedPlaceId, setSelectedPlaceId] = useState<number | string | null>(null);
  const [mobileTab, setMobileTab] = useState<"list" | "map">("list");

  // Tải danh sách địa điểm từ API thực tế của FastAPI (/api/v1/places/)
  useEffect(() => {
    async function fetchPlaces() {
      try {
        setIsLoading(true);
        setError(null);
        const data = await placeService.listPlaces(undefined, 0, 100);
        setPlaces(data);
        if (data.length > 0) {
          // Mặc định chọn địa điểm đầu tiên có tọa độ
          const firstWithCoords = data.find((p) => p.latitude && p.longitude);
          if (firstWithCoords) {
            setSelectedPlaceId(firstWithCoords.id);
          }
        }
      } catch (err: any) {
        console.error("Lỗi tải danh sách địa điểm:", err);
        setError("Không thể tải danh sách địa điểm từ máy chủ. Vui lòng thử lại sau.");
      } finally {
        setIsLoading(false);
      }
    }

    fetchPlaces();
  }, []);

  // Lọc theo từ khóa tìm kiếm
  const filteredPlaces = useMemo(() => {
    if (!searchQuery.trim()) return places;
    const q = searchQuery.toLowerCase().trim();
    return places.filter(
      (p) =>
        p.name.toLowerCase().includes(q) ||
        (p.address && p.address.toLowerCase().includes(q)) ||
        (p.description && p.description.toLowerCase().includes(q))
    );
  }, [places, searchQuery]);

  // Chuyển đổi PlaceItem thành MapPlace
  const mapPlaces: MapPlace[] = useMemo(() => {
    return filteredPlaces.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      address: p.address,
      latitude: p.latitude,
      longitude: p.longitude,
      category_id: p.category_id,
    }));
  }, [filteredPlaces]);

  const handleSelectPlace = (place: MapPlace | PlaceItem) => {
    setSelectedPlaceId(place.id);
    // Trên mobile, khi bấm xem trên bản đồ thì tự chuyển sang tab map
    setMobileTab("map");
  };

  return (
    <div className="flex flex-col h-screen max-h-screen bg-slate-950 text-slate-100 font-sans overflow-hidden">
      {/* 1. Header */}
      <header className="flex-shrink-0 z-20 flex items-center justify-between px-4 sm:px-6 py-3 bg-slate-900/90 backdrop-blur-xl border-b border-slate-800">
        <div className="flex items-center gap-3">
          <Link href="/" className="flex items-center gap-2 group">
            <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-teal-400 to-cyan-400 flex items-center justify-center text-slate-950 font-black text-sm shadow-md shadow-teal-500/20 group-hover:scale-105 transition-transform">
              🌴
            </div>
            <span className="font-bold text-base bg-gradient-to-r from-teal-300 via-cyan-200 to-white bg-clip-text text-transparent hidden sm:inline">
              TravelWise
            </span>
          </Link>
          <span className="text-slate-600 hidden sm:inline">/</span>
          <h1 className="text-sm font-semibold text-slate-200 flex items-center gap-1.5">
            <span>🗺️</span>
            <span>Khám phá Bản đồ Địa điểm</span>
          </h1>
        </div>

        <div className="flex items-center gap-2">
          {/* Mobile Switcher (List vs Map) */}
          <div className="flex md:hidden items-center p-0.5 rounded-xl bg-slate-800 border border-slate-700">
            <button
              type="button"
              onClick={() => setMobileTab("list")}
              className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                mobileTab === "list"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              Danh sách ({filteredPlaces.length})
            </button>
            <button
              type="button"
              onClick={() => setMobileTab("map")}
              className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                mobileTab === "map"
                  ? "bg-teal-500 text-slate-950 shadow-sm"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              Bản đồ
            </button>
          </div>

          <Link
            href="/trips"
            className="hidden sm:flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800/80 hover:bg-slate-800 border border-slate-700 text-xs font-medium text-slate-300 hover:text-white transition-all"
          >
            <span>📅</span>
            <span>Lịch trình</span>
          </Link>

          <Link
            href="/voice-guide"
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-cyan-400 text-slate-950 text-xs font-bold shadow-md shadow-teal-500/20 hover:brightness-105 transition-all"
          >
            <span>🎙️</span>
            <span>Voice Guide</span>
          </Link>
        </div>
      </header>

      {/* 2. Main Body Split View: List on left, Interactive Map on right */}
      <div className="flex-1 flex flex-col md:flex-row overflow-hidden relative">
        {/* Left Column: Places Directory */}
        <div
          className={`w-full md:w-[420px] lg:w-[460px] flex-shrink-0 flex flex-col h-full bg-slate-950 border-r border-slate-800/80 z-10 ${
            mobileTab === "map" ? "hidden md:flex" : "flex"
          }`}
        >
          {/* Search Box */}
          <div className="p-3.5 border-b border-slate-800/80 bg-slate-900/50">
            <div className="relative">
              <span className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400 text-sm">
                🔍
              </span>
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Tìm tên địa điểm, danh lam thắng cảnh..."
                className="w-full pl-9 pr-4 py-2 bg-slate-900 border border-slate-700/80 rounded-xl text-xs sm:text-sm text-slate-100 placeholder-slate-500 focus:outline-none focus:border-teal-400 transition-colors"
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery("")}
                  className="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-500 hover:text-slate-300"
                >
                  ✕
                </button>
              )}
            </div>

            <div className="flex items-center justify-between mt-2.5 px-1 text-xs text-slate-400 font-medium">
              <span>Tìm thấy {filteredPlaces.length} địa điểm</span>
              <span className="text-[11px] text-teal-400/90">Bản đồ Du lịch TravelWise</span>
            </div>
          </div>

          {/* Place Cards List */}
          <div className="flex-1 overflow-y-auto custom-scrollbar p-3 space-y-2.5">
            {isLoading && (
              <div className="flex flex-col items-center justify-center py-16 text-slate-400">
                <div className="w-7 h-7 rounded-full border-2 border-teal-400 border-t-transparent animate-spin mb-3" />
                <p className="text-xs">Đang tải danh sách địa điểm từ hệ thống...</p>
              </div>
            )}

            {error && (
              <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-300 text-xs">
                {error}
              </div>
            )}

            {!isLoading && !error && filteredPlaces.length === 0 && (
              <div className="text-center py-16 text-slate-500 text-xs">
                <p className="text-2xl mb-2">🏝️</p>
                <p>Không tìm thấy địa điểm nào phù hợp với từ khóa.</p>
              </div>
            )}

            {!isLoading &&
              filteredPlaces.map((place) => {
                const isSelected = selectedPlaceId === place.id;
                const hasCoords = place.latitude != null && place.longitude != null;
                const primaryImg = place.images?.find((img) => img.is_primary) || place.images?.[0];

                return (
                  <div
                    key={place.id}
                    onClick={() => handleSelectPlace(place)}
                    className={`p-3 rounded-2xl border transition-all cursor-pointer ${
                      isSelected
                        ? "bg-slate-900/90 border-teal-400/80 shadow-md shadow-teal-950/40 ring-1 ring-teal-400/30"
                        : "bg-slate-900/40 hover:bg-slate-900/80 border-slate-800/80 hover:border-slate-700"
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      {primaryImg?.url ? (
                        <img
                          src={primaryImg.url}
                          alt={primaryImg.description || place.name}
                          className="w-16 h-16 sm:w-20 sm:h-20 rounded-xl object-cover flex-shrink-0 border border-slate-700/60 shadow-sm"
                          loading="lazy"
                        />
                      ) : (
                        <div className="w-16 h-16 sm:w-20 sm:h-20 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-500 text-lg flex-shrink-0 border border-slate-700/40">
                          📍
                        </div>
                      )}

                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-1.5">
                          <Link
                            href={`/places/${place.id}`}
                            onClick={(e) => e.stopPropagation()}
                            className={`text-sm font-bold truncate hover:underline ${
                              isSelected ? "text-teal-300" : "text-slate-100"
                            }`}
                            title="Xem chi tiết địa điểm"
                          >
                            {place.name}
                          </Link>

                          {hasCoords && (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                handleSelectPlace(place);
                              }}
                              className={`flex-shrink-0 px-2 py-0.5 rounded-lg text-[10px] font-bold border transition-colors ${
                                isSelected
                                  ? "bg-teal-500 text-slate-950 border-teal-400"
                                  : "bg-slate-800/80 text-teal-300 border-teal-500/20 hover:bg-teal-500/20"
                              }`}
                              title="Xem vị trí trên bản đồ"
                            >
                              Bản đồ →
                            </button>
                          )}
                        </div>

                        {place.address && (
                          <p className="text-xs text-slate-400 mt-1 line-clamp-1 flex items-center gap-1">
                            <span>📍</span>
                            <span>{place.address}</span>
                          </p>
                        )}

                        {place.description && (
                          <p className="text-[11px] text-slate-400 mt-1 line-clamp-2 leading-relaxed">
                            {place.description}
                          </p>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
          </div>
        </div>

        {/* Right Column: Interactive MapLibre Map */}
        <div
          className={`flex-1 h-full relative overflow-hidden bg-slate-950 ${
            mobileTab === "list" ? "hidden md:block" : "block"
          }`}
        >
          <TravelMap
            places={mapPlaces}
            selectedPlaceId={selectedPlaceId}
            onPlaceSelect={handleSelectPlace}
            height="100%"
            className="h-full rounded-none border-0"
          />
        </div>
      </div>
    </div>
  );
}
