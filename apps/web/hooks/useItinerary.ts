"use client";

import { useState, useEffect, useCallback } from "react";
import { apiFetch } from "@/services/api";

export interface ActivityDetail {
  id?: number;
  activity_order?: number;
  place_id?: number;
  place_name: string;
  place_address?: string;
  time_slot?: string;
  custom_description?: string;
  estimated_cost?: number;
  latitude?: number;
  longitude?: number;
}

export interface DayDetail {
  id?: number;
  day_number: number;
  title?: string;
  theme?: string;
  notes?: string;
  activities: ActivityDetail[];
}

export interface ItineraryDetail {
  id?: number;
  trip_id: number;
  name?: string;
  destination_city?: string;
  destination_country?: string;
  days_count: number;
  status?: string;
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
      setItinerary(data);
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
