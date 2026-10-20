"use client";

import { useEffect, useState } from "react";
import { getTodayWeather } from "@/services/weather.service";
import type { WeatherResponse } from "@/types/weather";

const DA_NANG_COORDINATES = {
  latitude: 16.0544,
  longitude: 108.2022,
};

function getWeatherSummary(code: number): { icon: string; label: string } {
  if (code === 0) return { icon: "☀️", label: "Trời quang" };
  if ([1, 2, 3].includes(code)) return { icon: "⛅", label: "Có mây" };
  if ([45, 48].includes(code)) return { icon: "🌫️", label: "Sương mù" };
  if ([51, 53, 55, 56, 57].includes(code)) {
    return { icon: "🌦️", label: "Mưa phùn" };
  }
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) {
    return { icon: "🌧️", label: "Có mưa" };
  }
  if ([95, 96, 99].includes(code)) return { icon: "⛈️", label: "Dông" };
  return { icon: "🌡️", label: "Thời tiết thay đổi" };
}

function formatNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function formatTime(value: string): string {
  return new Intl.DateTimeFormat("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Ho_Chi_Minh",
  }).format(new Date(value));
}

export default function TodayWeatherCard() {
  const [weather, setWeather] = useState<WeatherResponse | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let isMounted = true;

    getTodayWeather(
      DA_NANG_COORDINATES.latitude,
      DA_NANG_COORDINATES.longitude
    )
      .then((data) => {
        if (isMounted) setWeather(data);
      })
      .catch(() => {
        if (isMounted) setError(true);
      });

    return () => {
      isMounted = false;
    };
  }, []);

  const daily = weather?.forecast[0];
  const summary = daily ? getWeatherSummary(daily.weather_code) : null;

  return (
    <section className="mx-auto max-w-6xl px-4 pb-4 pt-3">
      <div className="rounded-xl border border-cyan-500/15 bg-slate-900/55 px-3 py-2 shadow-sm shadow-cyan-500/5">
        <div className="flex min-h-10 flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <span className="text-base" aria-hidden="true">
              {summary?.icon || "🌤️"}
            </span>
            <p className="text-xs font-medium text-slate-300">
              Thời tiết hôm nay
            </p>
            <p className="text-xs font-semibold text-white">
              Đà Nẵng
            </p>
          </div>

          {weather && daily && summary ? (
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
              <span className="font-medium text-slate-200">{summary.label}</span>
              <span className="text-slate-300">
                {formatNumber(weather.current.temperature)}°C
              </span>
              <span className="text-slate-500">
                Cao {formatNumber(daily.temperature_max)}° · Thấp{" "}
                {formatNumber(daily.temperature_min)}°
              </span>
              <span className="text-slate-500">
                Mưa {formatNumber(daily.precipitation_probability)}%
              </span>
            </div>
          ) : error ? (
            <p className="text-xs text-amber-300">
              Chưa thể tải dữ liệu thời tiết lúc này.
            </p>
          ) : (
            <div className="h-5 w-48 animate-pulse rounded-md bg-slate-800/80" />
          )}
        </div>

        {weather && daily && (
          <p className="mt-1 pl-6 text-[10px] text-slate-500">
            Cảm nhận {formatNumber(weather.current.apparent_temperature)}°C ·
            Độ ẩm {formatNumber(weather.current.relative_humidity)}% · Gió{" "}
            {formatNumber(weather.current.wind_speed)} km/h · Cập nhật{" "}
            {formatTime(weather.current.time)}
          </p>
        )}
      </div>
    </section>
  );
}
