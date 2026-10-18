"use client";

import { useState, useEffect, useCallback } from "react";
import { apiFetch } from "@/services/api";

export interface TripListItem {
  id: number;
  name?: string;
  destination_city?: string;
  destination_country?: string;
  days_count: number;
  status: string;
  created_at?: string;
  updated_at?: string;
}

export interface CreateTripInput {
  name?: string;
  destination_city: string;
  destination_country?: string;
  start_date?: string;
  end_date?: string;
  duration_days?: number;
  conversation_id?: number;
  context?: unknown;
}

export interface UpdateTripInput {
  name?: string;
  status?: string;
  destination_city?: string;
  destination_country?: string;
  start_date?: string;
  end_date?: string;
}

interface TripListResponse {
  items: TripListItem[];
  total: number;
  page: number;
  page_size: number;
}

export function useTrips(limit: number = 20) {
  const [trips, setTrips] = useState<TripListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTrips = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await apiFetch<TripListResponse>(`/api/v1/trips?limit=${limit}`);
      setTrips(data.items || []);
      setTotal(data.total || 0);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không thể tải danh sách chuyến đi";
      setError(msg);
      // Fallback empty list
      setTrips([]);
    } finally {
      setIsLoading(false);
    }
  }, [limit]);

  useEffect(() => {
    fetchTrips();
  }, [fetchTrips]);

  const deleteTrip = useCallback(async (tripId: number) => {
    try {
      await apiFetch(`/api/v1/trips/${tripId}`, { method: "DELETE" });
      setTrips((prev) => prev.filter((t) => t.id !== tripId));
      setTotal((prev) => Math.max(0, prev - 1));
      return true;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không thể xóa chuyến đi";
      setError(msg);
      return false;
    }
  }, []);

  const createTrip = useCallback(async (input: CreateTripInput) => {
    const trip = await apiFetch<TripListItem>("/api/v1/trips", {
      method: "POST",
      body: JSON.stringify(input),
    });
    setTrips((prev) => [trip, ...prev]);
    setTotal((prev) => prev + 1);
    return trip;
  }, []);

  const updateTrip = useCallback(
    async (tripId: number, input: UpdateTripInput) => {
      const trip = await apiFetch<TripListItem>(`/api/v1/trips/${tripId}`, {
        method: "PATCH",
        body: JSON.stringify(input),
      });
      setTrips((prev) => prev.map((item) => (item.id === tripId ? trip : item)));
      return trip;
    },
    []
  );

  return {
    trips,
    total,
    isLoading,
    error,
    refreshTrips: fetchTrips,
    deleteTrip,
    createTrip,
    updateTrip,
  };
}
