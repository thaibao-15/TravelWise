"use client";

import React, { useState, useEffect, useMemo, useCallback } from "react";
import Link from "next/link";
import { placeService, PlaceItem, CategoryItem } from "@/services/place.service";
import { TravelMap, MapPlace } from "@/components/map/TravelMap";
import { PlaceReviewsModal } from "@/components/places/PlaceReviewsModal";

interface CategoryMeta {
  icon: string;
  color: string;
  badgeClass: string;
  activeClass: string;
}

const DEFAULT_CATEGORY_META: CategoryMeta = {
  icon: "📍",
  color: "#0d9488",
  badgeClass: "bg-teal-500/10 text-teal-300 border-teal-500/30",
  activeClass: "bg-teal-500 text-slate-950 shadow-teal-500/30 border-teal-400",
};

const CATEGORY_META_BY_ID: Record<number, CategoryMeta> = {
  1: {
    icon: "🌿",
    color: "#10b981", // Emerald
    badgeClass: "bg-emerald-500/10 text-emerald-300 border-emerald-500/30",
    activeClass: "bg-emerald-500 text-slate-950 shadow-emerald-500/30 border-emerald-400",
  },
  2: {
    icon: "🏛️",
    color: "#d97706", // Amber
    badgeClass: "bg-amber-500/10 text-amber-300 border-amber-500/30",
    activeClass: "bg-amber-500 text-slate-950 shadow-amber-500/30 border-amber-400",
  },
  3: {
    icon: "🍜",
    color: "#ea580c", // Orange
    badgeClass: "bg-orange-500/10 text-orange-300 border-orange-500/30",
    activeClass: "bg-orange-500 text-slate-950 shadow-orange-500/30 border-orange-400",
  },
  4: {
    icon: "☕",
    color: "#b45309", // Warm Brown
    badgeClass: "bg-amber-600/10 text-amber-200 border-amber-600/30",
    activeClass: "bg-amber-600 text-white shadow-amber-600/30 border-amber-500",
  },
  5: {
    icon: "🎡",
    color: "#ec4899", // Pink
    badgeClass: "bg-pink-500/10 text-pink-300 border-pink-500/30",
    activeClass: "bg-pink-500 text-white shadow-pink-500/30 border-pink-400",
  },
  6: {
    icon: "🛍️",
    color: "#e11d48", // Rose
    badgeClass: "bg-rose-500/10 text-rose-300 border-rose-500/30",
    activeClass: "bg-rose-500 text-white shadow-rose-500/30 border-rose-400",
  },
  7: {
    icon: "🏨",
    color: "#3b82f6", // Blue
    badgeClass: "bg-blue-500/10 text-blue-300 border-blue-500/30",
    activeClass: "bg-blue-500 text-white shadow-blue-500/30 border-blue-400",
  },
  8: {
    icon: "🏄",
    color: "#06b6d4", // Cyan
    badgeClass: "bg-cyan-500/10 text-cyan-300 border-cyan-500/30",
    activeClass: "bg-cyan-500 text-slate-950 shadow-cyan-500/30 border-cyan-400",
  },
  9: {
    icon: "💆",
    color: "#14b8a6", // Teal
    badgeClass: "bg-teal-500/10 text-teal-300 border-teal-500/30",
    activeClass: "bg-teal-500 text-slate-950 shadow-teal-500/30 border-teal-400",
  },
  10: {
    icon: "🚗",
    color: "#6366f1", // Indigo
    badgeClass: "bg-indigo-500/10 text-indigo-300 border-indigo-500/30",
    activeClass: "bg-indigo-500 text-white shadow-indigo-500/30 border-indigo-400",
  },
};

function getCategoryMeta(id?: number | null, name?: string | null): CategoryMeta {
  if (id && CATEGORY_META_BY_ID[id]) {
    return CATEGORY_META_BY_ID[id];
  }
  if (name) {
    const lower = name.toLowerCase();
    if (lower.includes("ẩm thực") || lower.includes("ăn")) return CATEGORY_META_BY_ID[3];
    if (lower.includes("khách sạn") || lower.includes("lưu trú")) return CATEGORY_META_BY_ID[7];
    if (lower.includes("văn hóa") || lower.includes("lịch sử") || lower.includes("tâm linh")) return CATEGORY_META_BY_ID[2];
    if (lower.includes("thiên nhiên") || lower.includes("cảnh quan")) return CATEGORY_META_BY_ID[1];
    if (lower.includes("cà phê") || lower.includes("cafe")) return CATEGORY_META_BY_ID[4];
    if (lower.includes("vui chơi") || lower.includes("giải trí")) return CATEGORY_META_BY_ID[5];
    if (lower.includes("mua sắm") || lower.includes("chợ")) return CATEGORY_META_BY_ID[6];
  }
  return DEFAULT_CATEGORY_META;
}

export default function PlacesPage() {
  const [categories, setCategories] = useState<CategoryItem[]>([]);
  const [selectedCategoryId, setSelectedCategoryId] = useState<number | null>(null);
  const [places, setPlaces] = useState<PlaceItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isCategoriesLoading, setIsCategoriesLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [searchQuery, setSearchQuery] = useState("");
  const [selectedPlaceId, setSelectedPlaceId] = useState<number | string | null>(null);
  const [mobileTab, setMobileTab] = useState<"list" | "map">("list");
  const [reviewModalPlace, setReviewModalPlace] = useState<PlaceItem | null>(null);

  // Cập nhật rating và số review của place trong danh sách khi có review mới
  const handleReviewSubmitted = useCallback(
    (updatedPlaceId: number, newRatingAvg: number, newReviewCount: number) => {
      setPlaces((prev) =>
        prev.map((p) =>
          p.id === updatedPlaceId
            ? { ...p, rating_avg: newRatingAvg, review_count: newReviewCount }
            : p
        )
      );
    },
    []
  );

  // 1. Tải danh sách Categories từ API /api/v1/categories/
  useEffect(() => {
    async function fetchCategories() {
      try {
        setIsCategoriesLoading(true);
        const data = await placeService.listCategories();
        setCategories(data);
      } catch (err: any) {
        console.error("Lỗi tải danh mục:", err);
      } finally {
        setIsCategoriesLoading(false);
      }
    }
    fetchCategories();
  }, []);

  // Map tra cứu nhanh Category theo ID
  const categoryMap = useMemo(() => {
    const map = new Map<number, CategoryItem>();
    categories.forEach((cat) => map.set(cat.id, cat));
    return map;
  }, [categories]);

  // 2. Tải danh sách địa điểm theo categoryId (sử dụng API /api/v1/places/?category_id=...)
  const fetchPlaces = useCallback(async (catId: number | null) => {
    try {
      setIsLoading(true);
      setError(null);
      const data = await placeService.listPlaces(catId ?? undefined, 0, 100);
      setPlaces(data);
      if (data.length > 0) {
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
  }, []);

  useEffect(() => {
    fetchPlaces(selectedCategoryId);
  }, [selectedCategoryId, fetchPlaces]);

  // Xử lý chọn danh mục
  const handleSelectCategory = (catId: number | null) => {
    if (selectedCategoryId === catId) return;
    setSelectedCategoryId(catId);
    setSelectedPlaceId(null);
  };

  // Lọc theo từ khóa tìm kiếm (trong danh sách địa điểm hiện có)
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

  // Chuyển đổi PlaceItem thành MapPlace có đầy đủ thông tin Category & màu sắc Marker
  const mapPlaces: MapPlace[] = useMemo(() => {
    return filteredPlaces.map((p) => {
      const cat = p.category_id ? categoryMap.get(p.category_id) : undefined;
      const meta = getCategoryMeta(p.category_id, cat?.name);
      const primaryImg = p.images?.find((img) => img.is_primary) || p.images?.[0];

      return {
        id: p.id,
        name: p.name,
        description: p.description,
        address: p.address,
        latitude: p.latitude,
        longitude: p.longitude,
        category_id: p.category_id,
        category_name: cat ? `${meta.icon} ${cat.name}` : undefined,
        pin_color: meta.color,
        image_url: primaryImg?.url || null,
        rating_avg: p.rating_avg,
        review_count: p.review_count,
      };
    });
  }, [filteredPlaces, categoryMap]);

  const handleSelectPlace = (place: MapPlace | PlaceItem) => {
    setSelectedPlaceId(place.id);
    setMobileTab("map");
  };

  // Tên category hiện tại đang chọn
  const currentCategoryName = useMemo(() => {
    if (selectedCategoryId === null) return "Tất cả danh mục";
    return categoryMap.get(selectedCategoryId)?.name || "Danh mục";
  }, [selectedCategoryId, categoryMap]);

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
          {/* Search Box & Category Filter Chips */}
          <div className="p-3.5 border-b border-slate-800/80 bg-slate-900/50 space-y-3">
            {/* Search Input */}
            <div className="relative">
              <span className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400 text-sm">
                🔍
              </span>
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={`Tìm trong ${currentCategoryName}...`}
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

            {/* Category Filter Pills (Scrollable) */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-[11px] font-semibold text-slate-400 px-0.5">
                <span className="flex items-center gap-1">
                  <span>🏷️</span>
                  <span>Danh mục địa điểm</span>
                </span>
                {selectedCategoryId !== null && (
                  <button
                    type="button"
                    onClick={() => handleSelectCategory(null)}
                    className="text-teal-400 hover:text-teal-300 hover:underline transition-colors text-[10px]"
                  >
                    Xem tất cả
                  </button>
                )}
              </div>

              <div className="flex items-center gap-1.5 overflow-x-auto pb-1.5 pt-0.5 scrollbar-thin scrollbar-thumb-slate-700">
                {/* Pill Tất cả */}
                <button
                  type="button"
                  onClick={() => handleSelectCategory(null)}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition-all border flex-shrink-0 ${
                    selectedCategoryId === null
                      ? "bg-teal-500 text-slate-950 border-teal-400 shadow-md shadow-teal-500/20 font-bold"
                      : "bg-slate-900/80 text-slate-400 border-slate-800 hover:text-white hover:border-slate-700"
                  }`}
                >
                  <span>✨</span>
                  <span>Tất cả</span>
                </button>

                {/* Pills Danh mục từ API */}
                {categories.map((cat) => {
                  const isSelected = selectedCategoryId === cat.id;
                  const meta = getCategoryMeta(cat.id, cat.name);

                  return (
                    <button
                      key={cat.id}
                      type="button"
                      onClick={() => handleSelectCategory(cat.id)}
                      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition-all border flex-shrink-0 ${
                        isSelected
                          ? `${meta.activeClass} shadow-md font-bold`
                          : "bg-slate-900/80 text-slate-300 border-slate-800 hover:text-white hover:border-slate-700"
                      }`}
                    >
                      <span>{meta.icon}</span>
                      <span>{cat.name}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Quick Status Bar */}
            <div className="flex items-center justify-between px-1 text-xs text-slate-400 font-medium">
              <span className="flex items-center gap-1">
                <span>📍</span>
                <span>
                  {isLoading ? "Đang tải..." : `Có ${filteredPlaces.length} địa điểm`}
                </span>
              </span>
              <span className="text-[11px] text-teal-400/90 truncate max-w-[180px]">
                {currentCategoryName}
              </span>
            </div>
          </div>

          {/* Place Cards List */}
          <div className="flex-1 overflow-y-auto custom-scrollbar p-3 space-y-2.5">
            {isLoading && (
              <div className="flex flex-col items-center justify-center py-16 text-slate-400">
                <div className="w-7 h-7 rounded-full border-2 border-teal-400 border-t-transparent animate-spin mb-3" />
                <p className="text-xs">Đang tải danh sách địa điểm theo danh mục...</p>
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
                <p>Không tìm thấy địa điểm nào phù hợp.</p>
                {selectedCategoryId !== null && (
                  <button
                    type="button"
                    onClick={() => handleSelectCategory(null)}
                    className="mt-3 px-3 py-1.5 rounded-lg bg-teal-500/10 text-teal-300 border border-teal-500/30 hover:bg-teal-500/20 text-xs"
                  >
                    Quay lại xem tất cả địa điểm
                  </button>
                )}
              </div>
            )}

            {!isLoading &&
              filteredPlaces.map((place) => {
                const isSelected = selectedPlaceId === place.id;
                const hasCoords = place.latitude != null && place.longitude != null;
                const primaryImg = place.images?.find((img) => img.is_primary) || place.images?.[0];
                const cat = place.category_id ? categoryMap.get(place.category_id) : undefined;
                const meta = getCategoryMeta(place.category_id, cat?.name);

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
                          {meta.icon}
                        </div>
                      )}

                      <div className="min-w-0 flex-1">
                        {/* Category & Rating Badges */}
                        <div className="mb-1 flex items-center justify-between gap-1 flex-wrap">
                          {cat && (
                            <span
                              className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-semibold border ${meta.badgeClass}`}
                            >
                              <span>{meta.icon}</span>
                              <span className="truncate max-w-[130px]">{cat.name}</span>
                            </span>
                          )}

                          {place.rating_avg != null && place.rating_avg > 0 ? (
                            <div className="flex items-center gap-1 text-[11px] font-bold text-amber-400 bg-amber-500/10 border border-amber-500/25 px-1.5 py-0.5 rounded-md">
                              <span>★</span>
                              <span>{place.rating_avg.toFixed(1)}</span>
                              <span className="text-[10px] text-slate-400 font-normal">
                                ({place.review_count || 0})
                              </span>
                            </div>
                          ) : (
                            <span className="text-[10px] text-slate-500 font-medium">
                              Chưa có đánh giá
                            </span>
                          )}
                        </div>

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

                          <div className="flex items-center gap-1.5 flex-shrink-0">
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                setReviewModalPlace(place);
                              }}
                              className="px-2 py-0.5 rounded-lg text-[10px] font-bold border transition-colors bg-amber-500/10 text-amber-300 border-amber-500/30 hover:bg-amber-500/20 flex items-center gap-1"
                              title="Xem hoặc viết nhận xét cho địa điểm này"
                            >
                              <span>⭐</span>
                              <span>Đánh giá {place.review_count ? `(${place.review_count})` : ""}</span>
                            </button>

                            {hasCoords && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleSelectPlace(place);
                                }}
                                className={`px-2 py-0.5 rounded-lg text-[10px] font-bold border transition-colors ${
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
          {/* Floating Category Filter Pills directly on Map */}
          <div className="absolute top-3 left-3 right-3 sm:left-4 sm:right-auto z-10 max-w-xl">
            <div className="flex items-center gap-1.5 p-1.5 bg-slate-900/85 backdrop-blur-md rounded-2xl border border-slate-700/70 shadow-lg shadow-black/40 overflow-x-auto scrollbar-none">
              <button
                type="button"
                onClick={() => handleSelectCategory(null)}
                className={`flex items-center gap-1 px-2.5 py-1 rounded-xl text-xs font-semibold whitespace-nowrap transition-all border ${
                  selectedCategoryId === null
                    ? "bg-teal-500 text-slate-950 border-teal-400 font-bold shadow-sm"
                    : "bg-slate-800/70 text-slate-300 border-slate-700/60 hover:text-white"
                }`}
              >
                <span>✨</span>
                <span>Tất cả ({mapPlaces.length})</span>
              </button>

              {categories.map((cat) => {
                const isSelected = selectedCategoryId === cat.id;
                const meta = getCategoryMeta(cat.id, cat.name);

                return (
                  <button
                    key={cat.id}
                    type="button"
                    onClick={() => handleSelectCategory(cat.id)}
                    className={`flex items-center gap-1 px-2.5 py-1 rounded-xl text-xs font-semibold whitespace-nowrap transition-all border ${
                      isSelected
                        ? `${meta.activeClass} font-bold shadow-sm`
                        : "bg-slate-800/70 text-slate-300 border-slate-700/60 hover:text-white"
                    }`}
                  >
                    <span>{meta.icon}</span>
                    <span>{cat.name}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Interactive Map */}
          <TravelMap
            places={mapPlaces}
            selectedPlaceId={selectedPlaceId}
            onPlaceSelect={handleSelectPlace}
            height="100%"
            className="h-full rounded-none border-0"
          />

          {/* Floating Category Legend at Bottom-Left of Map */}
          <div className="absolute bottom-3 left-3 z-10 hidden sm:block">
            <div className="bg-slate-900/85 backdrop-blur-md px-3 py-2 rounded-xl border border-slate-800/80 shadow-md shadow-black/40 text-[11px] text-slate-300 max-w-xs">
              <p className="font-bold text-slate-200 mb-1 flex items-center gap-1">
                <span>🗺️</span>
                <span>Chú thích danh mục</span>
              </p>
              <div className="flex flex-wrap gap-x-3 gap-y-1">
                {categories.slice(0, 6).map((cat) => {
                  const meta = getCategoryMeta(cat.id, cat.name);
                  return (
                    <div key={cat.id} className="flex items-center gap-1">
                      <span
                        className="w-2.5 h-2.5 rounded-full inline-block flex-shrink-0"
                        style={{ backgroundColor: meta.color }}
                      />
                      <span className="truncate max-w-[100px]">{cat.name}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      </div>
      {/* 3. Modal Đánh giá Địa điểm */}
      <PlaceReviewsModal
        place={reviewModalPlace}
        isOpen={!!reviewModalPlace}
        onClose={() => setReviewModalPlace(null)}
        onReviewSubmitted={handleReviewSubmitted}
      />
    </div>
  );
}
