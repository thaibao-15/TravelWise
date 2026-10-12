"use client";

import React, { useState } from "react";
import Link from "next/link";
import { useTrips } from "@/hooks/useTrips";

export default function TripsPage() {
  const { trips, isLoading, deleteTrip } = useTrips(50);
  const [filterStatus, setFilterStatus] = useState<string>("ALL");

  const filteredTrips =
    filterStatus === "ALL"
      ? trips
      : trips.filter((t) => t.status.toUpperCase() === filterStatus);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans">
      {/* Navigation Header */}
      <header className="sticky top-0 z-20 flex items-center justify-between px-6 py-4 bg-slate-900/80 backdrop-blur-xl border-b border-slate-800">
        <div className="flex items-center gap-3">
          <Link href="/chat" className="flex items-center gap-2 group">
            <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-teal-500 to-cyan-400 flex items-center justify-center text-slate-950 font-black text-sm shadow-md shadow-teal-500/20 group-hover:scale-105 transition-transform">
              TW
            </div>
            <span className="font-bold text-base bg-gradient-to-r from-teal-300 via-cyan-200 to-white bg-clip-text text-transparent">
              TravelWise
            </span>
          </Link>
          <span className="text-slate-600">/</span>
          <h1 className="text-sm font-semibold text-slate-300">
            Lịch trình của tôi
          </h1>
        </div>

        <div className="flex items-center gap-3">
          <Link
            href="/voice-guide"
            className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-gradient-to-r from-teal-500 to-cyan-500 text-slate-950 text-xs font-bold shadow-md shadow-teal-900/30 hover:brightness-110 transition-all"
          >
            <span>🎙️</span>
            <span>Mở AI Voice Guide</span>
          </Link>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-6xl mx-auto px-4 sm:px-6 py-8">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-8">
          <div>
            <h2 className="text-2xl font-black text-slate-100 tracking-tight">
              Kế hoạch & Lịch trình du lịch
            </h2>
            <p className="text-sm text-slate-400 mt-1">
              Quản lý các chuyến đi đã tạo cùng Trợ lý AI và tiếp tục thảo luận điều chỉnh.
            </p>
          </div>

          {/* Filters */}
          <div className="flex items-center gap-1.5 p-1 rounded-xl bg-slate-900 border border-slate-800 text-xs font-semibold">
            {["ALL", "GENERATED", "CONFIRMED", "DRAFT"].map((st) => (
              <button
                key={st}
                type="button"
                onClick={() => setFilterStatus(st)}
                className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer ${
                  filterStatus === st
                    ? "bg-teal-500/20 text-teal-300 border border-teal-500/30 font-bold"
                    : "text-slate-400 hover:text-slate-200"
                }`}
              >
                {st === "ALL"
                  ? "Tất cả"
                  : st === "GENERATED"
                  ? "Đã tạo AI"
                  : st === "CONFIRMED"
                  ? "Đã chốt"
                  : "Bản nháp"}
              </button>
            ))}
          </div>
        </div>

        {/* Trips Grid */}
        {isLoading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {[1, 2, 3].map((n) => (
              <div
                key={n}
                className="h-44 rounded-2xl bg-slate-900/50 border border-slate-800 animate-pulse p-5"
              />
            ))}
          </div>
        ) : filteredTrips.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {filteredTrips.map((trip) => (
              <Link
                key={trip.id}
                href={`/trips/${trip.id}`}
                className="group p-5 rounded-2xl bg-slate-900/80 hover:bg-slate-900 border border-slate-800 hover:border-teal-500/40 transition-all duration-200 shadow-md flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-center justify-between gap-2 mb-2">
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-teal-500/10 text-teal-300 border border-teal-500/20 uppercase tracking-wider">
                      {trip.status}
                    </span>
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-slate-400 font-medium">
                        📅 {trip.days_count} ngày
                      </span>
                      <button
                        type="button"
                        onClick={async (e) => {
                          e.preventDefault();
                          e.stopPropagation();
                          if (confirm(`Bạn có chắc muốn xóa chuyến đi "${trip.name || trip.destination_city || `#${trip.id}`}"?`)) {
                            await deleteTrip(trip.id);
                          }
                        }}
                        className="p-1 rounded text-slate-500 hover:text-rose-400 hover:bg-rose-500/15 transition-colors cursor-pointer text-xs"
                        title="Xóa chuyến đi"
                      >
                        🗑️
                      </button>
                    </div>
                  </div>

                  <h3 className="text-base font-bold text-slate-100 group-hover:text-teal-300 transition-colors">
                    {trip.name || trip.destination_city || `Chuyến đi #${trip.id}`}
                  </h3>

                  <p className="text-xs text-slate-400 mt-1 flex items-center gap-1.5">
                    <span>📍</span>
                    <span>
                      {trip.destination_city
                        ? `${trip.destination_city}${
                            trip.destination_country ? `, ${trip.destination_country}` : ""
                          }`
                        : "Việt Nam"}
                    </span>
                  </p>
                </div>

                <div className="mt-4 pt-4 border-t border-slate-800/80 flex items-center justify-between text-xs text-slate-400">
                  <span>Xem chi tiết lịch trình</span>
                  <span className="text-teal-400 group-hover:translate-x-1 transition-transform">
                    →
                  </span>
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <div className="p-12 text-center rounded-3xl bg-slate-900/40 border border-slate-800/80 max-w-lg mx-auto">
            <div className="text-4xl mb-3">🗺️</div>
            <h3 className="text-base font-bold text-slate-200">
              Chưa có chuyến đi nào được lưu
            </h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Bạn có thể bắt đầu trò chuyện với AI Tour Guide về điểm đến yêu thích để tự động tạo lịch trình đầu tiên.
            </p>
            <Link
              href="/chat"
              className="inline-flex items-center gap-2 mt-5 px-4 py-2.5 rounded-xl bg-gradient-to-r from-teal-500 to-cyan-500 text-slate-950 text-xs font-bold shadow-md shadow-teal-900/30 hover:brightness-110 transition-all"
            >
              <span>Trò chuyện để lên kế hoạch ngay</span>
              <span>→</span>
            </Link>
          </div>
        )}
      </main>
    </div>
  );
}
