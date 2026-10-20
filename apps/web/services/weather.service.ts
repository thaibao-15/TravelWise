import { apiFetch } from "@/services/api";
import type { WeatherResponse } from "@/types/weather";

export function getTodayWeather(
  latitude: number,
  longitude: number
): Promise<WeatherResponse> {
  const params = new URLSearchParams({
    latitude: String(latitude),
    longitude: String(longitude),
    forecast_days: "1",
  });

  return apiFetch<WeatherResponse>(`/api/v1/weather?${params.toString()}`);
}
