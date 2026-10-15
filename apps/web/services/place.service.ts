import { apiFetch } from "@/services/api";

export interface PlaceImageItem {
  id: number;
  place_id?: number;
  url?: string | null;
  description?: string | null;
  is_primary: boolean;
}

export interface PlaceItem {
  id: number;
  name: string;
  description?: string | null;
  address?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  category_id?: number | null;
  images?: PlaceImageItem[];
  restaurant_detail?: any;
  hotel_detail?: any;
}

export const placeService = {
  /**
   * Lấy danh sách địa điểm theo danh mục hoặc phân trang
   */
  async listPlaces(categoryId?: number, skip = 0, limit = 50): Promise<PlaceItem[]> {
    const params = new URLSearchParams();
    if (categoryId) params.append("category_id", String(categoryId));
    params.append("skip", String(skip));
    params.append("limit", String(limit));

    return await apiFetch<PlaceItem[]>(`/api/v1/places/?${params.toString()}`);
  },

  /**
   * Tìm kiếm địa điểm theo từ khóa tên hoặc địa chỉ
   */
  async searchPlaces(query: string, skip = 0, limit = 20): Promise<PlaceItem[]> {
    const params = new URLSearchParams({
      q: query,
      skip: String(skip),
      limit: String(limit),
    });
    return await apiFetch<PlaceItem[]>(`/api/v1/places/search?${params.toString()}`);
  },

  /**
   * Lấy chi tiết một địa điểm theo ID
   */
  async getPlace(placeId: number): Promise<PlaceItem> {
    return await apiFetch<PlaceItem>(`/api/v1/places/${placeId}`);
  },

  /**
   * Lấy danh sách hình ảnh của một địa điểm
   */
  async getPlaceImages(placeId: number): Promise<PlaceImageItem[]> {
    return await apiFetch<PlaceImageItem[]>(`/api/v1/places/${placeId}/images`);
  },

  /**
   * Tìm kiếm và xếp hạng địa điểm thực tế từ SQL Server phục vụ lập lịch trình
   */
  async searchForItinerary(
    context?: any,
    skip = 0,
    limit = 20
  ): Promise<any> {
    return await apiFetch<any>(`/api/v1/places/search-for-itinerary`, {
      method: "POST",
      body: JSON.stringify({ context, skip, limit }),
    });
  },
};
