"use client";

import { useState, useEffect, useCallback } from "react";
import { placeService, PlaceItem } from "@/services/place.service";

export function usePlaces(categoryId?: number) {
  const [places, setPlaces] = useState<PlaceItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchPlaces = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await placeService.listPlaces(categoryId);
      setPlaces(data);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không thể tải danh sách địa điểm";
      setError(msg);
      setPlaces([]);
    } finally {
      setIsLoading(false);
    }
  }, [categoryId]);

  useEffect(() => {
    fetchPlaces();
  }, [fetchPlaces]);

  const search = useCallback(async (query: string) => {
    if (!query.trim()) {
      return fetchPlaces();
    }
    setIsLoading(true);
    setError(null);
    try {
      const results = await placeService.searchPlaces(query.trim());
      setPlaces(results);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Lỗi tìm kiếm địa điểm";
      setError(msg);
    } finally {
      setIsLoading(false);
    }
  }, [fetchPlaces]);

  return {
    places,
    isLoading,
    error,
    search,
    refresh: fetchPlaces,
  };
}
