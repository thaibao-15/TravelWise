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
  rating_avg?: number | null;
  review_count?: number | null;
  is_deleted?: boolean;
  created_at?: string;
  updated_at?: string;
  images?: PlaceImageItem[];
  restaurant_detail?: {
    cuisine_type?: string | null;
    price_range?: string | null;
    is_vegetarian?: boolean | null;
  } | null;
  hotel_detail?: {
    star_rating?: number | null;
    price_per_night?: number | null;
    amenities?: string | null;
  } | null;
}
