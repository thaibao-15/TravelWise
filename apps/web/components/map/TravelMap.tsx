"use client";

import React, { useEffect, useRef, useState, useCallback } from "react";
import {
  Map as MapLibreMap,
  Marker,
  Popup,
  LngLatBounds,
  NavigationControl,
  AttributionControl,
  GeolocateControl,
  setWorkerUrl,
} from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import {
  getMapStyle,
  DEFAULT_MAP_CENTER,
  DEFAULT_MAP_ZOOM,
  getInitialMapCenter,
  VIETNAM_SOVEREIGNTY_POINTS,
  SovereigntyPoint,
} from "@/lib/map-config";

// Cấu hình đường dẫn Web Worker tĩnh để Next.js (Turbopack) tải trực tiếp từ /public
// Giải quyết dứt điểm lỗi: "Worker failed to load. Check that the worker URL is correct."
if (typeof window !== "undefined") {
  setWorkerUrl("/maplibre-gl-worker.mjs");
}

export interface MapPlace {
  id: string | number;
  name: string;
  description?: string | null;
  address?: string | null;
  latitude: number | null | undefined;
  longitude: number | null | undefined;
  category_id?: number | null;
  order?: number | string; // Thứ tự trong lịch trình (nếu có)
  day_number?: number; // Ngày trong chuyến đi (1, 2, 3...)
  time?: string | null; // Thời gian bắt đầu hoặc time_slot (ví dụ "08:30" hoặc "08:30 - 10:00")
  badge_label?: string; // Nhãn hiển thị trực tiếp trên pin marker (ví dụ "1", "N1-1")
}

export interface TravelMapProps {
  places: MapPlace[];
  selectedPlaceId?: string | number | null;
  onPlaceSelect?: (place: MapPlace) => void;
  className?: string;
  height?: string;
  interactive?: boolean;
  showLocateButton?: boolean;
  defaultToUserLocation?: boolean;
  showSovereigntyMarkers?: boolean;
}

/**
 * Kiểm tra tính hợp lệ của tọa độ vĩ độ (-90 đến 90) và kinh độ (-180 đến 180).
 */
export function isValidCoordinate(
  lat: number | null | undefined,
  lng: number | null | undefined
): boolean {
  if (lat === null || lat === undefined || lng === null || lng === undefined) {
    return false;
  }
  const nLat = Number(lat);
  const nLng = Number(lng);
  if (isNaN(nLat) || isNaN(nLng)) return false;
  if (nLat < -90 || nLat > 90) return false;
  if (nLng < -180 || nLng > 180) return false;
  return true;
}

export function TravelMap({
  places,
  selectedPlaceId,
  onPlaceSelect,
  className = "",
  height = "100%",
  interactive = true,
  showLocateButton = true,
  defaultToUserLocation = true,
  showSovereigntyMarkers = true,
}: TravelMapProps) {
  const mapContainerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const markersMapRef = useRef<Map<string | number, { marker: Marker; popup: Popup; place: MapPlace }>>(new Map());
  const userMarkerRef = useRef<Marker | null>(null);
  const sovereigntyMarkersRef = useRef<Marker[]>([]);

  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isLocating, setIsLocating] = useState(false);
  const [locationMessage, setLocationMessage] = useState<{
    type: "error" | "info" | "success";
    text: string;
  } | null>(null);

  // Lọc danh sách các địa điểm có tọa độ hợp lệ
  const validPlaces = places.filter((p) => isValidCoordinate(p.latitude, p.longitude));

  // Tạo DOM element an toàn chống XSS cho Popup
  const createPopupContent = useCallback((place: MapPlace): HTMLElement => {
    const container = document.createElement("div");
    container.className = "travelwise-popup-content p-2 min-w-[200px] max-w-[280px] font-sans text-slate-900";

    // Tag Ngày & Giờ (nếu thuộc lịch trình)
    if (place.day_number != null || place.time) {
      const dayPill = document.createElement("div");
      dayPill.className = "inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-teal-50 text-[10px] font-bold text-teal-800 border border-teal-200 mb-1.5";
      dayPill.textContent = `🗓️ Ngày ${place.day_number || 1}${place.time ? ` • ⏰ ${place.time}` : ""}`;
      container.appendChild(dayPill);
    }

    const titleEl = document.createElement("h4");
    titleEl.className = "font-bold text-sm text-slate-950 leading-snug";
    titleEl.textContent = place.name;
    container.appendChild(titleEl);

    if (place.address && place.address.trim()) {
      const addrEl = document.createElement("p");
      addrEl.className = "text-xs text-slate-600 mt-1 flex items-start gap-1 leading-normal";
      addrEl.textContent = `📍 ${place.address}`;
      container.appendChild(addrEl);
    }

    if (place.description && place.description.trim()) {
      const descEl = document.createElement("p");
      descEl.className = "text-[11px] text-slate-500 mt-1.5 line-clamp-3 leading-relaxed border-t border-slate-100 pt-1";
      descEl.textContent = place.description;
      container.appendChild(descEl);
    }

    return container;
  }, []);

  // Màu sắc chủ đạo cho Pin giọt nước
  const getPinColor = (dayNumber?: number, isSelected?: boolean): string => {
    if (isSelected) return "#e11d48"; // Rose-600 khi được chọn
    switch (dayNumber) {
      case 1:
        return "#0d9488"; // Teal
      case 2:
        return "#4f46e5"; // Indigo
      case 3:
        return "#ea580c"; // Orange
      case 4:
        return "#059669"; // Emerald
      default:
        // Màu xanh Navy chuẩn Google/Apple Maps như ảnh mẫu của người dùng
        return dayNumber && dayNumber > 4 ? "#e11d48" : "#0d3b85";
    }
  };

  /**
   * Tạo Custom Marker DOM element dạng Teardrop Pin chuẩn Maps (như ảnh người dùng yêu cầu)
   * - Hình dáng giọt nước đỉnh tròn, đáy nhọn.
   * - Viền trắng sắc nét (stroke-width: 1.8).
   * - Lõi chấm tròn trắng ở giữa (hoặc số thứ tự hoạt động).
   * - Kích thước to vừa phải (26px x 34px), có bóng đổ ellipse chân thực.
   */
  const createMarkerElement = useCallback((place: MapPlace, isSelected: boolean): HTMLElement => {
    const el = document.createElement("div");
    el.className = `travelwise-map-marker-root cursor-pointer select-none ${
      isSelected ? "z-30" : "z-10 hover:z-20"
    }`;

    const hasBadge = place.badge_label != null || place.order != null;
    const labelText =
      place.badge_label != null
        ? place.badge_label
        : place.order != null
          ? String(place.order)
          : "";

    const pinColor = getPinColor(place.day_number, isSelected);

    // Xử lý chiều rộng nếu có nhãn text dài (ví dụ: "N1-1")
    const isLongLabel = labelText.length > 2;
    const width = isLongLabel ? 34 : 26;
    const height = 34;
    const cx = width / 2;

    const centerContent = hasBadge
      ? `
        <circle cx="${cx}" cy="13" r="${isLongLabel ? 8.5 : 6}" fill="#ffffff" />
        <text x="${cx}" y="16.5" text-anchor="middle" font-size="${isLongLabel ? 8 : 9}" font-weight="900" font-family="system-ui, sans-serif" fill="${pinColor}">
          ${labelText}
        </text>
      `
      : `
        <circle cx="${cx}" cy="13" r="4.5" fill="#ffffff" />
      `;

    // Path giọt nước đối xứng chuẩn: đỉnh tròn r=12, mũi nhọn tại đáy y=32.5
    const pathD = isLongLabel
      ? `M${cx} 1 C8 1 2 6.5 2 13 C2 21.5 ${cx} 32.5 ${cx} 32.5 C${cx} 32.5 ${width - 2} 21.5 ${width - 2} 13 C${width - 2} 6.5 ${width - 8} 1 ${cx} 1Z`
      : `M13 1 C6.37 1 1 6.37 1 13 C1 21.8 13 32.5 13 32.5 C13 32.5 25 21.8 25 13 C25 6.37 19.63 1 13 1Z`;

    el.className = `travelwise-map-marker-root cursor-pointer select-none ${
      isSelected ? "is-selected z-30" : "z-10 hover:z-20"
    }`;

    el.innerHTML = `
      <div class="travelwise-marker-inner origin-bottom">
        <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" fill="none" xmlns="http://www.w3.org/2000/svg" class="filter drop-shadow-md">
          <!-- Bóng đổ mặt đất -->
          <ellipse cx="${cx}" cy="33" rx="${width * 0.22}" ry="1.4" fill="rgba(0, 0, 0, 0.3)" />
          <!-- Thân giọt nước -->
          <path d="${pathD}" fill="${pinColor}" stroke="#ffffff" stroke-width="1.8" stroke-linejoin="round" />
          <!-- Lõi chấm trắng / text số thứ tự -->
          ${centerContent}
        </svg>
      </div>
    `;

    return el;
  }, []);

  // Hàm tạo hoặc cập nhật User Location Marker có hiệu ứng radar pulse an toàn
  const renderUserMarker = useCallback((map: MapLibreMap, lng: number, lat: number, accuracy?: number) => {
    if (userMarkerRef.current) {
      userMarkerRef.current.remove();
      userMarkerRef.current = null;
    }

    const userEl = document.createElement("div");
    userEl.className = "travelwise-user-marker-root cursor-pointer select-none";
    userEl.innerHTML = `
      <div class="relative flex items-center justify-center">
        <div class="absolute w-10 h-10 rounded-full bg-cyan-400/30 animate-ping pointer-events-none"></div>
        <div class="relative w-5 h-5 rounded-full bg-cyan-400 border-2 border-white shadow-lg shadow-cyan-500/50 flex items-center justify-center">
          <div class="w-1.5 h-1.5 rounded-full bg-slate-950"></div>
        </div>
      </div>
    `;

    const accuracyText = accuracy
      ? `<p class="text-[10px] text-slate-400 mt-0.5">Bán kính chính xác: ~${Math.round(accuracy)}m</p>`
      : "";

    const popup = new Popup({
      offset: [0, -15],
      closeButton: true,
      closeOnClick: false,
      className: "travelwise-maplibre-popup",
    }).setHTML(`
      <div class="p-1 min-w-[180px] text-slate-100 font-sans">
        <div class="flex items-center gap-1.5 text-cyan-400 font-bold text-xs mb-1">
          <span class="inline-block w-2 h-2 rounded-full bg-cyan-400 animate-pulse"></span>
          Vị trí hiện tại của bạn
        </div>
        <p class="text-[11px] text-slate-300">Tọa độ: ${lat.toFixed(5)}, ${lng.toFixed(5)}</p>
        ${accuracyText}
      </div>
    `);

    const newMarker = new Marker({ element: userEl, anchor: "center" })
      .setLngLat([lng, lat])
      .setPopup(popup)
      .addTo(map);

    userMarkerRef.current = newMarker;
    return newMarker;
  }, []);

  // 1. Khởi tạo MapLibre instance một lần duy nhất
  useEffect(() => {
    if (!mapContainerRef.current) return;
    if (mapRef.current) return;

    setIsLoading(true);
    setLoadError(null);

    let map: MapLibreMap;
    try {
      const styleConfig = getMapStyle();
      const initialCenter = getInitialMapCenter();

      map = new MapLibreMap({
        container: mapContainerRef.current,
        style: styleConfig,
        center: initialCenter,
        zoom: DEFAULT_MAP_ZOOM,
        interactive: interactive,
        attributionControl: false,
      });

      // Tự động co giãn kích thước ghim/nhãn theo mức zoom bản đồ (Dynamic Zoom-Adaptive Scaling)
      const updateZoomScale = () => {
        const z = map.getZoom();
        let scale = 1.0;
        if (z <= 4.5) scale = 0.55;
        else if (z <= 7.5) scale = 0.75;
        else if (z <= 11.5) scale = 0.95;
        else scale = 1.15;

        mapContainerRef.current?.style.setProperty("--travelwise-marker-scale", String(scale));
      };

      map.on("zoom", updateZoomScale);
      updateZoomScale();

      // Thêm nút điều hướng (Zoom +/- và Compass)
      if (interactive) {
        map.addControl(
          new NavigationControl({ showCompass: true, showZoom: true }),
          "top-right"
        );

        // Thêm nút định vị bản địa của MapLibre
        const geolocateControl = new GeolocateControl({
          positionOptions: {
            enableHighAccuracy: true,
          },
          trackUserLocation: true,
          showUserLocation: true,
          showAccuracyCircle: true,
        });
        map.addControl(geolocateControl, "top-right");
      }

      // Thêm Attribution Control hiển thị rõ ràng bản quyền
      map.addControl(
        new AttributionControl({
          compact: false,
          customAttribution: "© TravelWise Platform",
        }),
        "bottom-right"
      );

      map.on("load", () => {
        setIsLoading(false);

        // Hiển thị các điểm mốc khẳng định chủ quyền Hoàng Sa, Trường Sa và Biển Đông
        if (showSovereigntyMarkers) {
          sovereigntyMarkersRef.current.forEach((m) => m.remove());
          sovereigntyMarkersRef.current = [];

          VIETNAM_SOVEREIGNTY_POINTS.forEach((point) => {
            const labelEl = document.createElement("div");
            labelEl.className = "travelwise-sovereignty-root cursor-pointer select-none bg-transparent";
            labelEl.innerHTML = `
              <div class="travelwise-sovereignty-inner origin-center">
                <div class="travelwise-sovereignty-text flex items-center justify-center">
                  ${point.badge}
                </div>
              </div>
            `;

            const popup = new Popup({
              offset: [0, -10],
              closeButton: true,
              closeOnClick: false,
              className: "travelwise-maplibre-popup",
            }).setHTML(`
              <div class="p-2 min-w-[200px] max-w-[260px] font-sans">
                <div class="flex items-center gap-1.5 text-cyan-400 font-bold text-xs mb-1 border-b border-slate-700/80 pb-1">
                  <span>${point.name}</span>
                </div>
                <p class="text-[11px] text-slate-300 leading-relaxed">${point.description}</p>
              </div>
            `);

            const marker = new Marker({ element: labelEl, anchor: "center" })
              .setLngLat(point.coordinates)
              .setPopup(popup)
              .addTo(map);

            sovereigntyMarkersRef.current.push(marker);
          });
        }

        // Tự động định vị vị trí hiện tại của người dùng làm trung tâm mặc định
        if (defaultToUserLocation && typeof window !== "undefined" && navigator.geolocation) {
          navigator.geolocation.getCurrentPosition(
            (pos) => {
              const { latitude, longitude, accuracy } = pos.coords;
              try {
                localStorage.setItem(
                  "travelwise_user_location",
                  JSON.stringify({ lng: longitude, lat: latitude })
                );
              } catch {}

              if (mapRef.current) {
                renderUserMarker(mapRef.current, longitude, latitude, accuracy);

                // Nếu danh sách địa điểm trống hoặc không có địa điểm nào được chọn, căn trung tâm bản đồ về vị trí của người dùng
                if (validPlaces.length === 0 || !selectedPlaceId) {
                  mapRef.current.flyTo({
                    center: [longitude, latitude],
                    zoom: 14,
                    essential: true,
                  });
                }
              }
            },
            (err) => {
              console.debug("Auto geolocation notice:", err.message);
            },
            { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
          );
        }
      });

      map.on("error", (e) => {
        const errorMessage = e.error?.message || "";
        if (errorMessage.includes("style") || errorMessage.includes("source")) {
          console.warn("MapLibre GL warning:", e);
          setLoadError("Không thể tải nguồn bản đồ. Vui lòng kiểm tra kết nối mạng.");
        } else {
          console.debug("MapLibre minor event:", e);
        }
      });

      mapRef.current = map;
    } catch (err: any) {
      console.error("Map initialization failed:", err);
      setLoadError("Không thể khởi tạo bản đồ MapLibre.");
      setIsLoading(false);
      return;
    }

    return () => {
      // Dọn dẹp markers
      markersMapRef.current.forEach(({ marker }) => marker.remove());
      markersMapRef.current.clear();

      sovereigntyMarkersRef.current.forEach((m) => m.remove());
      sovereigntyMarkersRef.current = [];

      if (userMarkerRef.current) {
        userMarkerRef.current.remove();
        userMarkerRef.current = null;
      }

      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
  }, [interactive, defaultToUserLocation, showSovereigntyMarkers, renderUserMarker]);

  // 2. Cập nhật Markers và Viewport Bounds khi `places` hoặc `selectedPlaceId` thay đổi
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    // Xóa tất cả marker cũ để tránh nhân đôi
    markersMapRef.current.forEach(({ marker }) => marker.remove());
    markersMapRef.current.clear();

    if (validPlaces.length === 0) return;

    const bounds = new LngLatBounds();

    validPlaces.forEach((place) => {
      const lng = Number(place.longitude);
      const lat = Number(place.latitude);
      const isSelected = selectedPlaceId === place.id;

      // Mở rộng bounding box
      bounds.extend([lng, lat]);

      // Tạo marker element an toàn không bị giật
      const markerEl = createMarkerElement(place, isSelected);

      // Tạo popup mở phía trên đầu pin
      const popup = new Popup({
        offset: [0, -33],
        closeButton: true,
        closeOnClick: false,
        className: "travelwise-maplibre-popup",
      }).setDOMContent(createPopupContent(place));

      // Đặt anchor = "bottom" để mũi nhọn chỉ đúng tọa độ
      const marker = new Marker({ element: markerEl, anchor: "bottom" })
        .setLngLat([lng, lat])
        .setPopup(popup)
        .addTo(map);

      // Bắt sự kiện click marker
      markerEl.addEventListener("click", () => {
        onPlaceSelect?.(place);
      });

      markersMapRef.current.set(place.id, { marker, popup, place });

      // Nếu đang được chọn, tự động mở popup
      if (isSelected) {
        marker.togglePopup();
      }
    });

    // Tự động điều chỉnh khung nhìn bản đồ (Camera)
    if (map.loaded()) {
      adjustCamera(map, validPlaces, bounds, selectedPlaceId);
    } else {
      map.once("load", () => {
        adjustCamera(map, validPlaces, bounds, selectedPlaceId);
      });
    }
  }, [places, selectedPlaceId, createMarkerElement, createPopupContent, onPlaceSelect, validPlaces]);

  // Hàm phụ trợ căn chỉnh Camera
  const adjustCamera = (
    map: MapLibreMap,
    placesList: MapPlace[],
    bounds: LngLatBounds,
    selectedId?: string | number | null
  ) => {
    if (selectedId && markersMapRef.current.has(selectedId)) {
      const item = markersMapRef.current.get(selectedId)!;
      const lng = Number(item.place.longitude);
      const lat = Number(item.place.latitude);
      map.flyTo({
        center: [lng, lat],
        zoom: 15,
        speed: 1.2,
        essential: true,
      });
      item.marker.getPopup()?.addTo(map);
      return;
    }

    if (placesList.length === 1) {
      const single = placesList[0];
      map.flyTo({
        center: [Number(single.longitude), Number(single.latitude)],
        zoom: 14,
        essential: true,
      });
    } else if (placesList.length > 1) {
      map.fitBounds(bounds, {
        padding: { top: 60, bottom: 60, left: 60, right: 60 },
        maxZoom: 15,
        duration: 800,
        essential: true,
      });
    }
  };

  // Xử lý xác định vị trí hiện tại của người dùng qua HTML5 Geolocation API
  const handleLocateUser = useCallback(() => {
    if (typeof window === "undefined" || !navigator.geolocation) {
      setLocationMessage({
        type: "error",
        text: "Trình duyệt của bạn không hỗ trợ định vị GPS.",
      });
      return;
    }

    setIsLocating(true);
    setLocationMessage(null);

    navigator.geolocation.getCurrentPosition(
      (position) => {
        setIsLocating(false);
        const { latitude, longitude, accuracy } = position.coords;

        const map = mapRef.current;
        if (!map) return;

        try {
          localStorage.setItem(
            "travelwise_user_location",
            JSON.stringify({ lng: longitude, lat: latitude })
          );
        } catch {}

        const marker = renderUserMarker(map, longitude, latitude, accuracy);
        marker.togglePopup();

        // Di chuyển camera mượt mà đến vị trí người dùng
        map.flyTo({
          center: [longitude, latitude],
          zoom: 15.5,
          speed: 1.4,
          curve: 1.2,
          essential: true,
        });

        setLocationMessage({
          type: "success",
          text: `Đã xác định vị trí của bạn (độ chính xác ~${Math.round(accuracy)}m)`,
        });

        setTimeout(() => {
          setLocationMessage(null);
        }, 4000);
      },
      (error) => {
        setIsLocating(false);
        let errorText = "Không thể lấy vị trí hiện tại của bạn.";
        if (error.code === error.PERMISSION_DENIED) {
          errorText = "Bạn chưa cấp quyền vị trí. Vui lòng bật quyền truy cập vị trí trên trình duyệt.";
        } else if (error.code === error.POSITION_UNAVAILABLE) {
          errorText = "Không nhận được tín hiệu định vị GPS từ thiết bị.";
        } else if (error.code === error.TIMEOUT) {
          errorText = "Quá thời gian xác định vị trí. Vui lòng thử lại.";
        }
        setLocationMessage({
          type: "error",
          text: errorText,
        });
        setTimeout(() => {
          setLocationMessage(null);
        }, 5000);
      },
      {
        enableHighAccuracy: true,
        timeout: 12000,
        maximumAge: 10000,
      }
    );
  }, [renderUserMarker]);

  return (
    <div className={`relative w-full overflow-hidden rounded-2xl bg-slate-900 border border-slate-800 ${className}`} style={{ height }}>
      {/* Container của MapLibre */}
      <div ref={mapContainerRef} className="w-full h-full" />

      {/* Loading Overlay */}
      {isLoading && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-slate-950/70 backdrop-blur-sm transition-opacity">
          <div className="w-8 h-8 rounded-full border-2 border-teal-400 border-t-transparent animate-spin mb-2" />
          <p className="text-xs text-slate-300 font-medium">Đang tải bản đồ TravelWise...</p>
        </div>
      )}

      {/* Error Overlay */}
      {loadError && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-slate-950/85 p-4 text-center">
          <span className="text-2xl mb-2">⚠️</span>
          <p className="text-xs text-rose-300 font-semibold mb-2">{loadError}</p>
          <button
            type="button"
            onClick={() => {
              setLoadError(null);
              setIsLoading(true);
              if (mapRef.current) {
                mapRef.current.remove();
                mapRef.current = null;
              }
              window.location.reload();
            }}
            className="px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-xs text-slate-200 border border-slate-700 cursor-pointer transition-colors"
          >
            Thử tải lại
          </button>
        </div>
      )}

      {/* Empty State Overlay khi danh sách places không có địa điểm hợp lệ */}
      {!isLoading && !loadError && validPlaces.length === 0 && (
        <div className="absolute top-4 left-4 z-10 px-3.5 py-2 rounded-xl bg-slate-900/90 border border-slate-800 backdrop-blur-md shadow-lg pointer-events-none">
          <p className="text-xs text-slate-400 flex items-center gap-1.5">
            <span>ℹ️</span>
            <span>Chưa có địa điểm nào có tọa độ để hiển thị</span>
          </p>
        </div>
      )}

      {/* Badge tổng số địa điểm trên bản đồ */}
      {!isLoading && !loadError && validPlaces.length > 0 && (
        <div className="absolute top-4 left-4 z-10 px-3 py-1.5 rounded-xl bg-slate-900/90 border border-slate-800 backdrop-blur-md shadow-lg">
          <p className="text-xs font-semibold text-teal-300 flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-teal-400 animate-pulse" />
            <span>{validPlaces.length} địa điểm trên bản đồ</span>
          </p>
        </div>
      )}

      {/* Nút định vị vị trí hiện tại của tôi */}
      {showLocateButton && interactive && (
        <button
          type="button"
          onClick={handleLocateUser}
          disabled={isLocating}
          className="absolute bottom-6 left-4 z-10 flex items-center gap-2 px-3 py-2 rounded-xl bg-slate-900/90 hover:bg-slate-800 text-slate-200 hover:text-cyan-400 border border-slate-700/80 hover:border-cyan-500/50 shadow-xl backdrop-blur-md transition-all active:scale-95 disabled:opacity-60 text-xs font-medium cursor-pointer"
          title="Xác định vị trí hiện tại của tôi trên bản đồ"
        >
          {isLocating ? (
            <>
              <span className="w-3.5 h-3.5 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin" />
              <span>Đang dò GPS...</span>
            </>
          ) : (
            <>
              <span className="text-sm">📍</span>
              <span>Vị trí của tôi</span>
            </>
          )}
        </button>
      )}

      {/* Toast thông báo trạng thái định vị */}
      {locationMessage && (
        <div
          className={`absolute bottom-16 left-4 z-20 max-w-xs px-3 py-2 rounded-xl text-xs font-medium backdrop-blur-md shadow-xl border transition-all animate-in fade-in slide-in-from-bottom-2 ${
            locationMessage.type === "error"
              ? "bg-rose-950/90 text-rose-200 border-rose-800 shadow-rose-950/50"
              : "bg-teal-950/90 text-teal-200 border-teal-800 shadow-teal-950/50"
          }`}
        >
          <div className="flex items-start gap-2">
            <span>{locationMessage.type === "error" ? "⚠️" : "✅"}</span>
            <p className="flex-1 leading-snug">{locationMessage.text}</p>
            <button
              type="button"
              onClick={() => setLocationMessage(null)}
              className="text-slate-400 hover:text-white ml-1 cursor-pointer"
            >
              ✕
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
