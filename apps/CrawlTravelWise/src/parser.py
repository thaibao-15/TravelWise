from __future__ import annotations

import re
from typing import Optional, Dict, Any, List
from playwright.async_api import Page


class GoogleMapsParser:
    """
    Parser bóc tách thông tin địa điểm Google Maps.
    Sử dụng các thuộc tính bền vững (data-item-id, aria-label, role, regex pattern)
    để không bị phá vỡ cấu trúc khi Google Maps đổi tên class CSS ngẫu nhiên.
    """

    @staticmethod
    def extract_cid_and_coords_from_url(url: str) -> Dict[str, Optional[float | str]]:
        """
        Trích xuất CID và vĩ độ/kinh độ từ URL Google Maps.
        Ví dụ URL:
        https://www.google.com/maps/place/.../@16.061234,108.223456,17z/data=!4m6!3m5!1s0x31421...:0x123456789abc...
        """
        coords_cid: Dict[str, Optional[float | str]] = {
            "latitude": None,
            "longitude": None,
            "cid": None,
            "query_place_id": None
        }

        # 1. Trích xuất tọa độ @lat,lng
        coord_match = re.search(r"@(-?\d+\.\d+),(-?\d+\.\d+)", url)
        if coord_match:
            try:
                coords_cid["latitude"] = float(coord_match.group(1))
                coords_cid["longitude"] = float(coord_match.group(2))
            except (ValueError, TypeError):
                pass

        # 2. Trích xuất CID hex từ chuỗi data=!4m...:0x[hex]
        cid_match = re.search(r":0x([0-9a-fA-F]+)", url)
        if cid_match:
            try:
                cid_hex = cid_match.group(1)
                coords_cid["cid"] = str(int(cid_hex, 16))
            except (ValueError, TypeError):
                coords_cid["cid"] = cid_match.group(1)

        # 3. Trích xuất Feature ID / Place ID nếu có
        place_id_match = re.search(r"!1s(0x[0-9a-fA-F]+:[0-9a-fA-Fx]+)", url)
        if place_id_match:
            coords_cid["query_place_id"] = place_id_match.group(1)

        return coords_cid

    @classmethod
    async def parse_place_detail(cls, page: Page, fallback_url: str = "") -> Dict[str, Any]:
        """
        Bóc tách chi tiết thông tin từ trang chi tiết của một địa điểm (tab chi tiết).
        """
        current_url = page.url or fallback_url
        geo_info = cls.extract_cid_and_coords_from_url(current_url)

        # 1. Tên địa điểm (h1 có class hoặc role='main' h1)
        name = ""
        try:
            h1_elem = page.locator("h1.DUwDvf, div[role='main'] h1").first
            if await h1_elem.is_visible(timeout=3000):
                name = (await h1_elem.inner_text()).strip()
        except Exception:
            pass

        # 2. Không bóc tách đánh giá sao & lượt review (Mặc định None / null)
        rating: Optional[float] = None
        review_count: Optional[int] = None

        # 3. Phân loại / Danh mục (Category)
        category: str = ""
        try:
            cat_elem = page.locator("button.DkEaL, button[jsaction*='pane.rating.category']").first
            if await cat_elem.is_visible(timeout=1500):
                category = (await cat_elem.inner_text()).strip()
        except Exception:
            pass

        # 4. Địa chỉ (Address) - dùng thuộc tính data-item-id="address" hoặc aria-label chứa Địa chỉ
        address: str = ""
        try:
            addr_elem = page.locator("button[data-item-id='address'] div.fontBodyMedium, button[aria-label*='Địa chỉ:']").first
            if await addr_elem.is_visible(timeout=1500):
                address = (await addr_elem.inner_text()).strip()
                address = re.sub(r"^Địa chỉ:\s*", "", address)
        except Exception:
            pass

        # 5. Số điện thoại (Phone)
        phone: str = ""
        try:
            phone_elem = page.locator("button[data-item-id^='phone:'] div.fontBodyMedium, button[aria-label*='Số điện thoại:']").first
            if await phone_elem.is_visible(timeout=1500):
                phone = (await phone_elem.inner_text()).strip()
                phone = re.sub(r"^Số điện thoại:\s*", "", phone)
        except Exception:
            pass

        # 6. Website
        website: str = ""
        try:
            web_elem = page.locator("a[data-item-id='authority']").first
            if await web_elem.is_visible(timeout=1500):
                website = (await web_elem.get_attribute("href") or "").strip()
        except Exception:
            pass

        # 7. Giờ mở cửa / Trạng thái hoạt động
        opening_hours: str = ""
        try:
            hours_elem = page.locator("div[data-item-id*='oh'] .fontBodyMedium, div[aria-label*='giờ mở cửa']").first
            if await hours_elem.is_visible(timeout=1500):
                opening_hours = (await hours_elem.inner_text()).strip()
        except Exception:
            pass

        # 8. Mức giá (Price Level nếu có: $, $$, $$$)
        price_level: str = ""
        try:
            price_elem = page.locator("span[aria-label*='Giá:']").first
            if await price_elem.is_visible(timeout=1000):
                price_level = await price_elem.get_attribute("aria-label") or ""
        except Exception:
            pass

        return {
            "name": name,
            "category": category,
            "rating": rating,
            "review_count": review_count,
            "address": address,
            "phone": phone,
            "website": website,
            "opening_hours": opening_hours,
            "price_level": price_level,
            "latitude": geo_info["latitude"],
            "longitude": geo_info["longitude"],
            "cid": geo_info["cid"],
            "google_maps_url": current_url,
        }

