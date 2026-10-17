"use client";

import { useState, useEffect, useCallback } from "react";
import { apiFetch } from "@/services/api";

export interface ItineraryPlaceSummary {
  place_id: number;
  name: string;
  category?: string;
  address?: string;
  description?: string;
  latitude?: number;
  longitude?: number;
}

export interface ActivityDetail {
  id: number;
  itinerary_day_id?: number;
  order_index?: number;
  activity_order?: number;
  activity_type?: string;
  place_id?: number;
  place?: ItineraryPlaceSummary | null;
  title?: string;
  description?: string;
  start_time?: string;
  end_time?: string;
  duration_minutes?: number;
  estimated_cost?: number;
  travel_duration_minutes?: number;
  travel_distance_km?: number;
  note?: string;

  // Normalized helper fields
  place_name: string;
  place_address?: string;
  time_slot?: string;
  custom_description?: string;
  latitude?: number;
  longitude?: number;
  day_number?: number;
}

export interface DayDetail {
  id?: number;
  trip_id?: number;
  day_number: number;
  date?: string;
  title?: string;
  description?: string;
  theme?: string;
  notes?: string;
  activities: ActivityDetail[];
}

export interface ItineraryDetail {
  id?: number;
  trip_id: number;
  name?: string;
  destination?: string;
  destination_city?: string;
  destination_country?: string;
  duration_days?: number;
  days_count: number;
  status?: string;
  start_date?: string;
  end_date?: string;
  days: DayDetail[];
}

export function useItinerary(tripId: number | null) {
  const [itinerary, setItinerary] = useState<ItineraryDetail | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchItinerary = useCallback(async () => {
    if (!tripId) return;
    setIsLoading(true);
    setError(null);
    try {
      const data = await apiFetch<any>(`/api/v1/trips/${tripId}/itinerary`);
      if (data && Array.isArray(data.days)) {
        const normalizedDays: DayDetail[] = data.days
          .sort((a: any, b: any) => (a.day_number || 0) - (b.day_number || 0))
          .map((day: any) => {
            const sortedActs = (day.activities || [])
              .sort(
                (a: any, b: any) =>
                  (a.order_index ?? a.activity_order ?? 0) -
                  (b.order_index ?? b.activity_order ?? 0)
              )
              .map((act: any, idx: number) => {
                const p = act.place || null;
                const order = act.order_index ?? act.activity_order ?? idx + 1;
                const timeSlot =
                  act.start_time && act.end_time
                    ? `${act.start_time} - ${act.end_time}`
                    : act.start_time || act.time_slot || undefined;
                return {
                  ...act,
                  id: act.id ?? idx + 1,
                  order_index: order,
                  activity_order: order,
                  day_number: day.day_number,
                  place_name: p?.name || act.title || act.place_name || `Điểm dừng ${order}`,
                  place_address: p?.address || act.place_address || undefined,
                  latitude: p?.latitude ?? act.latitude ?? undefined,
                  longitude: p?.longitude ?? act.longitude ?? undefined,
                  custom_description:
                    act.description || p?.description || act.custom_description || undefined,
                  time_slot: timeSlot,
                  note: act.note,
                };
              });

            return {
              ...day,
              activities: sortedActs,
            };
          });

        setItinerary({
          ...data,
          days_count: data.duration_days || normalizedDays.length || data.days_count || 1,
          days: normalizedDays,
        });
      } else {
        setItinerary(data);
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không thể tải chi tiết lịch trình";
      setError(msg);
    } finally {
      setIsLoading(false);
    }
  }, [tripId]);

  useEffect(() => {
    if (tripId) {
      fetchItinerary();
    }
  }, [tripId, fetchItinerary]);

  const editItinerary = useCallback(
    async (targetTripId: number, options: { change_prompt: string }) => {
      setIsEditing(true);
      setError(null);
      try {
        // Attempt edit endpoint or regenerate with instruction
        const res = await apiFetch<{ message?: string; status?: string; itinerary?: any }>(
          `/api/v1/trips/${targetTripId}/itinerary/edit`,
          {
            method: "POST",
            body: JSON.stringify({
              change_prompt: options.change_prompt,
            }),
          }
        );
        // Refresh itinerary
        await fetchItinerary();
        return {
          message: res.message || "Đã cập nhật lịch trình thành công theo yêu cầu!",
        };
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : "Không thể chỉnh sửa lịch trình";
        setError(msg);
        throw err;
      } finally {
        setIsEditing(false);
      }
    },
    [fetchItinerary]
  );

  const confirmTrip = useCallback(
    async (targetTripId: number) => {
      try {
        await apiFetch(`/api/v1/trips/${targetTripId}`, {
          method: "PATCH",
          body: JSON.stringify({ status: "CONFIRMED" }),
        });
        await fetchItinerary();
        return true;
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : "Không thể chốt chuyến đi";
        setError(msg);
        return false;
      }
    },
    [fetchItinerary]
  );

  return {
    itinerary,
    isLoading,
    isEditing,
    error,
    editItinerary,
    confirmTrip,
    refreshItinerary: fetchItinerary,
  };
}
