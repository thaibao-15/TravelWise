import { apiFetch } from "@/services/api";

export interface ReviewImageItem {
  id: number;
  review_id: number;
  image_url: string;
  caption?: string | null;
  display_order: number;
  created_at: string;
}

export interface ReviewAuthorItem {
  id: number;
  email: string;
  full_name?: string | null;
  avatar_url?: string | null;
}

export interface PlaceReviewItem {
  id: number;
  place_id: number;
  user_id: number;
  rating: number;
  title?: string | null;
  comment?: string | null;
  trip_type?: string | null;
  visited_at?: string | null;
  helpful_count: number;
  owner_reply?: string | null;
  owner_replied_at?: string | null;
  is_visible: boolean;
  created_at: string;
  updated_at: string;
  images: ReviewImageItem[];
  user?: ReviewAuthorItem | null;
  is_helpful_voted?: boolean;
}

export interface PlaceReviewListResponse {
  total: number;
  rating_avg: number;
  rating_breakdown: Record<string, number>;
  items: PlaceReviewItem[];
}

export interface CreateReviewImagePayload {
  image_url: string;
  caption?: string;
  display_order?: number;
}

export interface CreateReviewPayload {
  rating: number;
  title?: string;
  comment?: string;
  trip_type?: string;
  visited_at?: string;
  images?: CreateReviewImagePayload[];
}

export interface HelpfulVoteResponse {
  review_id: number;
  voted: boolean;
  helpful_count: number;
  message: string;
}

export const reviewService = {
  /**
   * Lấy danh sách đánh giá của một địa điểm
   */
  async listPlaceReviews(
    placeId: number,
    params?: {
      skip?: number;
      limit?: number;
      rating?: number;
      trip_type?: string;
      sort_by?: "newest" | "helpful" | "rating_high" | "rating_low";
    }
  ): Promise<PlaceReviewListResponse> {
    const query = new URLSearchParams();
    if (params?.skip != null) query.append("skip", String(params.skip));
    if (params?.limit != null) query.append("limit", String(params.limit));
    if (params?.rating != null) query.append("rating", String(params.rating));
    if (params?.trip_type) query.append("trip_type", params.trip_type);
    if (params?.sort_by) query.append("sort_by", params.sort_by);

    const queryString = query.toString();
    const endpoint = `/api/v1/places/${placeId}/reviews${queryString ? `?${queryString}` : ""}`;
    return await apiFetch<PlaceReviewListResponse>(endpoint);
  },

  /**
   * Tạo đánh giá mới cho địa điểm
   */
  async createReview(placeId: number, data: CreateReviewPayload): Promise<PlaceReviewItem> {
    return await apiFetch<PlaceReviewItem>(`/api/v1/places/${placeId}/reviews`, {
      method: "POST",
      body: JSON.stringify(data),
    });
  },

  /**
   * Chỉnh sửa bài đánh giá
   */
  async updateReview(
    reviewId: number,
    data: Partial<CreateReviewPayload>
  ): Promise<PlaceReviewItem> {
    return await apiFetch<PlaceReviewItem>(`/api/v1/reviews/${reviewId}`, {
      method: "PUT",
      body: JSON.stringify(data),
    });
  },

  /**
   * Xóa bài đánh giá
   */
  async deleteReview(reviewId: number): Promise<{ success: boolean; message: string }> {
    return await apiFetch<{ success: boolean; message: string }>(`/api/v1/reviews/${reviewId}`, {
      method: "DELETE",
    });
  },

  /**
   * Bấm hoặc hủy bình chọn hữu ích (Like / Helpful)
   */
  async toggleHelpfulVote(reviewId: number): Promise<HelpfulVoteResponse> {
    return await apiFetch<HelpfulVoteResponse>(`/api/v1/reviews/${reviewId}/helpful`, {
      method: "POST",
    });
  },

  /**
   * Thêm ảnh vào đánh giá đã có
   */
  async addReviewImage(
    reviewId: number,
    image: CreateReviewImagePayload
  ): Promise<ReviewImageItem> {
    return await apiFetch<ReviewImageItem>(`/api/v1/reviews/${reviewId}/images`, {
      method: "POST",
      body: JSON.stringify(image),
    });
  },

  /**
   * Xóa một ảnh trong bài đánh giá
   */
  async deleteReviewImage(imageId: number): Promise<{ success: boolean; message: string }> {
    return await apiFetch<{ success: boolean; message: string }>(
      `/api/v1/reviews/images/${imageId}`,
      {
        method: "DELETE",
      }
    );
  },
};
