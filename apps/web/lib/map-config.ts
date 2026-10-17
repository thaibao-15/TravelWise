import type { StyleSpecification } from "maplibre-gl";

/**
 * Cấu hình Style Specification cho Esri World Street Map.
 * - Nguồn bản đồ toàn cầu sạch sẽ, uy tín từ Esri.
 * - Tuyệt đối KHÔNG có đường lưỡi bò, KHÔNG có các nhãn sai lệch tại Biển Đông.
 * - Tốc độ tải cực nhanh tại Việt Nam qua CDN toàn cầu, hỗ trợ CORS *.
 * - Hoàn toàn MIỄN PHÍ, KHÔNG cần API key, KHÔNG có watermark.
 */
export const ESRI_WORLD_STREET_STYLE: StyleSpecification = {
  version: 8,
  sources: {
    "esri-street-tiles": {
      type: "raster",
      tiles: [
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}",
      ],
      tileSize: 256,
      attribution:
        '&copy; <a href="https://www.esri.com/" target="_blank" rel="noopener noreferrer">Esri</a> | Khẳng định chủ quyền Hoàng Sa &amp; Trường Sa thuộc Việt Nam 🇻🇳',
      maxzoom: 19,
    },
  },
  layers: [
    {
      id: "esri-street-layer",
      type: "raster",
      source: "esri-street-tiles",
      minzoom: 0,
      maxzoom: 19,
    },
  ],
};

/**
 * Tùy chọn nguồn OpenStreetMap tiêu chuẩn (Mirror)
 */
export const OPENSTREETMAP_RASTER_STYLE: StyleSpecification = {
  version: 8,
  sources: {
    "osm-raster-tiles": {
      type: "raster",
      tiles: [
        "https://tile.openstreetmap.de/{z}/{x}/{y}.png",
      ],
      tileSize: 256,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors | Hoàng Sa &amp; Trường Sa là của Việt Nam 🇻🇳',
      maxzoom: 19,
    },
  },
  layers: [
    {
      id: "osm-raster-layer",
      type: "raster",
      source: "osm-raster-tiles",
      minzoom: 0,
      maxzoom: 19,
    },
  ],
};

export const DEFAULT_MAP_CENTER: [number, number] = [108.2022, 16.0544];
export const DEFAULT_MAP_ZOOM = 12;

/**
 * Lấy tọa độ trung tâm mặc định cho bản đồ:
 * 1. Ưu tiên vị trí GPS hiện tại của người dùng đã lưu trong localStorage (nếu có).
 * 2. Mặc định dự phòng: Đà Nẵng, Việt Nam [108.2022, 16.0544].
 */
export function getInitialMapCenter(): [number, number] {
  if (typeof window !== "undefined") {
    try {
      const cached = localStorage.getItem("travelwise_user_location");
      if (cached) {
        const parsed = JSON.parse(cached);
        if (parsed?.lat != null && parsed?.lng != null) {
          const lng = Number(parsed.lng);
          const lat = Number(parsed.lat);
          if (!isNaN(lng) && !isNaN(lat) && lng >= -180 && lng <= 180 && lat >= -90 && lat <= 90) {
            return [lng, lat];
          }
        }
      }
    } catch {
      // Bỏ qua lỗi truy cập localStorage nếu có
    }
  }
  return DEFAULT_MAP_CENTER;
}

/**
 * Trả về style URL hoặc StyleSpecification cho MapLibre:
 * 1. Ưu tiên NEXT_PUBLIC_MAP_STYLE_URL (nếu người dùng cấu hình Goong Maps hoặc style riêng)
 * 2. Mặc định: Dùng ESRI_WORLD_STREET_STYLE (Sạch sẽ, không nhãn sai lệch, miễn phí 100%, không cần key)
 */
export function getMapStyle(): string | StyleSpecification {
  const envStyleUrl = process.env.NEXT_PUBLIC_MAP_STYLE_URL;
  if (envStyleUrl && envStyleUrl.trim().length > 0) {
    return envStyleUrl.trim();
  }

  return ESRI_WORLD_STREET_STYLE;
}

export interface SovereigntyPoint {
  id: string;
  name: string;
  subTitle: string;
  coordinates: [number, number]; // [kinh độ, vĩ độ]
  badge: string;
  description: string;
}

/**
 * Danh sách các điểm mốc khẳng định chủ quyền lãnh thổ thiêng liêng của Việt Nam trên Biển Đông
 */
export const VIETNAM_SOVEREIGNTY_POINTS: SovereigntyPoint[] = [
  {
    id: "hoang-sa",
    name: "Quần đảo Hoàng Sa ",
    subTitle: "Huyện Hoàng Sa, TP. Đà Nẵng",
    coordinates: [112.0, 16.5],
    badge: "Quần đảo Hoàng Sa ",
    description:
      "Quần đảo Hoàng Sa là phần lãnh thổ thiêng liêng không thể tách rời của nước Cộng hòa Xã hội Chủ nghĩa Việt Nam, thuộc địa giới hành chính của huyện Hoàng Sa, thành phố Đà Nẵng.",
  },
  {
    id: "truong-sa",
    name: "Quần đảo Trường Sa ",
    subTitle: "Huyện Trường Sa, Tỉnh Khánh Hòa",
    coordinates: [114.3, 9.8],
    badge: "Quần đảo Trường Sa ",
    description:
      "Quần đảo Trường Sa là phần lãnh thổ thiêng liêng không thể tách rời của nước Cộng hòa Xã hội Chủ nghĩa Việt Nam, thuộc địa giới hành chính của huyện Trường Sa, tỉnh Khánh Hòa.",
  },
  {
    id: "bien-dong",
    name: "Biển Đông ",
    subTitle: "Vùng biển chủ quyền Việt Nam",
    coordinates: [113.2, 13.2],
    badge: "Biển Đông",
    description:
      "Vùng biển và thềm lục địa thuộc chủ quyền, quyền chủ quyền và quyền tài phán của Việt Nam theo Công ước Liên Hợp Quốc về Luật Biển (UNCLOS) năm 1982.",
  },
];
