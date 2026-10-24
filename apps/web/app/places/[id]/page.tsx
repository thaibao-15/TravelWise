"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { placeService, PlaceItem } from "@/services/place.service";
import { TravelMap, MapPlace } from "@/components/map/TravelMap";
import { PlaceReviewsModal } from "@/components/places/PlaceReviewsModal";

export default function PlaceDetailPage() {
  const params = useParams();
  const placeIdStr = params?.id as string;
  const placeId = placeIdStr ? parseInt(placeIdStr, 10) : null;

  const [place, setPlace] = useState<PlaceItem | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isReviewOpen, setIsReviewOpen] = useState(false);

  useEffect(() => {
    if (!placeId) return;

    async function fetchPlace() {
      try {
        setIsLoading(true);
        setError(null);
        const data = await placeService.getPlace(placeId!);
        setPlace(data);
      } catch (err: any) {
        console.error("Lỗi khi tải chi tiết địa điểm:", err);
        setError("Không tìm thấy thông tin địa điểm hoặc lỗi kết nối.");
      } finally {
        setIsLoading(false);
      }
    }

    fetchPlace();
  }, [placeId]);

  const mapPlaces: MapPlace[] = place
    ? [
        {
          id: place.id,
          name: place.name,
          description: place.description,
          address: place.address,
          latitude: place.latitude,
          longitude: place.longitude,
          category_id: place.category_id,
        },
      ]
    : [];

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans">
      {/* Header */}
      <header className="sticky top-0 z-20 flex items-center justify-between px-4 sm:px-6 py-3 bg-slate-900/90 backdrop-blur-xl border-b border-slate-800">
        <div className="flex items-center gap-3">
          <Link
            href="/places"
            className="p-2 rounded-xl bg-slate-800/80 hover:bg-slate-800 text-slate-300 hover:text-white transition-colors text-xs font-semibold flex items-center gap-1"
          >
            ← Tất cả địa điểm
          </Link>
          <span className="text-slate-600">/</span>
          <h1 className="text-sm font-bold text-slate-200 truncate max-w-xs sm:max-w-md">
            {place?.name || "Chi tiết Địa điểm"}
          </h1>
        </div>

        <Link
          href={`/voice-guide?q=${encodeURIComponent(`Hãy giới thiệu cho tôi về ${place?.name || "địa điểm này"}`)}`}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-cyan-400 text-slate-950 text-xs font-bold shadow-md shadow-teal-500/20 hover:brightness-105 transition-all"
        >
          <span>🎙️</span>
          <span>Hỏi AI về điểm này</span>
        </Link>
      </header>

      {/* Main Content */}
      <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8">
        {isLoading ? (
          <div className="space-y-4">
            <div className="h-48 rounded-2xl bg-slate-900 border border-slate-800 animate-pulse" />
            <div className="h-96 rounded-2xl bg-slate-900 border border-slate-800 animate-pulse" />
          </div>
        ) : error ? (
          <div className="p-8 rounded-2xl bg-slate-900 border border-rose-500/30 text-center space-y-3">
            <p className="text-sm text-rose-300 font-semibold">{error}</p>
            <Link
              href="/places"
              className="inline-block px-4 py-2 rounded-xl bg-slate-800 text-xs font-semibold text-slate-200 hover:bg-slate-700 transition-colors"
            >
              Quay lại bản đồ địa điểm
            </Link>
          </div>
        ) : place ? (
          <div className="space-y-6">
            {/* Overview Card */}
            <div className="p-6 rounded-3xl bg-slate-900/80 border border-slate-800 shadow-xl backdrop-blur-md">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 border-b border-slate-800">
                <div>
                  <h2 className="text-2xl font-black text-slate-100 tracking-tight">
                    {place.name}
                  </h2>
                  {place.address && (
                    <p className="text-xs text-slate-400 mt-1 flex items-center gap-1.5">
                      <span>📍</span>
                      <span>{place.address}</span>
                    </p>
                  )}
                </div>

                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-[11px] font-semibold text-teal-300 bg-teal-500/10 border border-teal-500/25 px-2.5 py-1 rounded-full">
                    Tọa độ: {place.latitude?.toFixed(4)}, {place.longitude?.toFixed(4)}
                  </span>

                  <button
                    type="button"
                    onClick={() => setIsReviewOpen(true)}
                    className="flex items-center gap-1.5 text-xs font-bold text-amber-300 bg-amber-500/15 hover:bg-amber-500/25 border border-amber-500/30 px-3 py-1 rounded-full transition-colors shadow-sm"
                  >
                    <span>★</span>
                    <span>
                      {place.rating_avg != null && place.rating_avg > 0
                        ? `${place.rating_avg.toFixed(1)} (${place.review_count || 0} đánh giá)`
                        : "Viết đánh giá"}
                    </span>
                  </button>
                </div>
              </div>

              {place.description && (
                <div className="pt-4 text-sm text-slate-300 leading-relaxed font-normal">
                  {place.description}
                </div>
              )}
            </div>

            {/* Image Gallery */}
            {place.images && place.images.length > 0 && (
              <div className="rounded-3xl overflow-hidden border border-slate-800 bg-slate-900/60 p-5 shadow-xl">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <span className="text-base">📸</span>
                    <h3 className="text-sm font-bold text-slate-200">
                      Hình ảnh thực tế ({place.images.length})
                    </h3>
                  </div>
                  <span className="text-[11px] text-teal-400 font-medium">
                    TravelWise Gallery
                  </span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
                  {place.images.map((img) => (
                    <div
                      key={img.id}
                      className="group relative rounded-2xl overflow-hidden border border-slate-800 bg-slate-950/60"
                    >
                      <img
                        src={img.url || ""}
                        alt={img.description || place.name}
                        className="w-full h-48 object-cover group-hover:scale-105 transition-transform duration-300"
                        loading="lazy"
                      />
                      {img.is_primary && (
                        <span className="absolute top-2.5 left-2.5 px-2 py-0.5 rounded-md bg-teal-500/90 text-slate-950 font-bold text-[10px] shadow-sm backdrop-blur-sm">
                          Ảnh chính
                        </span>
                      )}
                      {img.description && (
                        <div className="p-3 bg-slate-900/90 text-xs text-slate-300 line-clamp-2">
                          {img.description}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Interactive OpenStreetMap Map */}
            <div className="rounded-3xl overflow-hidden border border-slate-800 shadow-2xl bg-slate-900">
              <div className="p-4 border-b border-slate-800 flex items-center justify-between bg-slate-900/90">
                <div className="flex items-center gap-2">
                  <span className="text-base">🗺️</span>
                  <h3 className="text-xs sm:text-sm font-bold text-slate-200">
                    Vị trí trên Bản đồ OpenStreetMap
                  </h3>
                </div>
                <span className="text-[11px] text-teal-400 font-medium">
                  MapLibre GL JS
                </span>
              </div>

              <div className="h-[380px] sm:h-[480px] w-full">
                <TravelMap
                  places={mapPlaces}
                  selectedPlaceId={place.id}
                  height="100%"
                />
              </div>
            </div>
          </div>
        ) : null}
      </main>

      {place && (
        <PlaceReviewsModal
          place={place}
          isOpen={isReviewOpen}
          onClose={() => setIsReviewOpen(false)}
          onReviewSubmitted={(id, avg, count) => {
            setPlace((prev) =>
              prev ? { ...prev, rating_avg: avg, review_count: count } : null
            );
          }}
        />
      )}
    </div>
  );
}
