"""
Module bóc tách thông tin chi tiết của địa điểm:
- Tọa độ GPS (latitude, longitude) qua Regex
- Tên địa điểm, Đánh giá, Số lượt review
- Địa chỉ, Quận/Huyện, Số điện thoại, Website
- Bóc tách hình ảnh chính (Image URL) của địa điểm
- Bóc tách bảng giờ mở cửa theo từng thứ trong tuần (day_of_week, open_time, close_time)
- Giá cả / Hạng sao khách sạn (Price level / Star rating)
"""

from datetime import datetime, timezone
import re
from typing import Any, Dict, List, Optional, Tuple
from playwright.async_api import Page, TimeoutError as PlaywrightTimeoutError

from src.config import DANANG_DISTRICTS, SELECTORS


def extract_coordinates_from_url(url: str) -> Tuple[Optional[float], Optional[float]]:
    """Trích xuất vĩ độ (latitude) và kinh độ (longitude) từ chuỗi URL Google Maps bằng Regex."""
    match_at = re.search(r"@(-?\d+\.\d+),(-?\d+\.\d+)", url)
    if match_at:
        try:
            return float(match_at.group(1)), float(match_at.group(2))
        except (ValueError, TypeError):
            pass

    match_data = re.search(r"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)", url)
    if match_data:
        try:
            return float(match_data.group(1)), float(match_data.group(2))
        except (ValueError, TypeError):
            pass

    return None, None


def extract_district(address: str) -> Optional[str]:
    """Tìm tên Quận / Huyện thuộc Đà Nẵng từ địa chỉ."""
    if not address:
        return None
    for district in DANANG_DISTRICTS:
        pattern = r"\b" + re.escape(district) + r"\b"
        if re.search(pattern, address, re.IGNORECASE):
            return district
    return None


def parse_schedule_days(raw_hours_text: str) -> List[Dict[str, Any]]:
    """
    Phân tích chuỗi giờ mở cửa thành các bản ghi theo ngày trong tuần:
    day_of_week: 1 (Chủ nhật) đến 7 (Thứ bảy) hoặc 2-8 theo chuẩn SQL Server:
    Quy ước SQL Server DATEFIRST: 1 = Thứ Hai, ..., 7 = Chủ Nhật (hoặc 1 = Chủ nhật)
    Ở đây dùng chuẩn: 1: Chủ nhật, 2: Thứ Hai, 3: Thứ Ba, 4: Thứ Tư, 5: Thứ Năm, 6: Thứ Sáu, 7: Thứ Bảy.
    """
    results: List[Dict[str, Any]] = []
    if not raw_hours_text:
        return results

    # Nếu ghi "Mở cả ngày" hoặc "Mở cửa 24 giờ"
    if any(k in raw_hours_text.lower() for k in ["mở cả ngày", "24 giờ", "24/24", "24 hours"]):
        for day in range(1, 8):
            results.append({
                "day_of_week": day,
                "open_time": "00:00:00",
                "close_time": "23:59:00",
            })
        return results

    # Tìm mẫu giờ: hh:mm - hh:mm (ví dụ 07:00 - 22:30 hoặc 7:00 – 23:00)
    time_matches = re.findall(r"(\d{1,2}:\d{2})\s*[–-]\s*(\d{1,2}:\d{2})", raw_hours_text)
    if time_matches:
        open_t, close_t = time_matches[0]
        # Chuẩn hóa về dạng HH:MM:SS
        if len(open_t.split(":")[0]) == 1:
            open_t = "0" + open_t
        if len(close_t.split(":")[0]) == 1:
            close_t = "0" + close_t

        for day in range(1, 8):
            results.append({
                "day_of_week": day,
                "open_time": f"{open_t}:00",
                "close_time": f"{close_t}:00",
            })

    return results


async def extract_place_details(
    page: Page,
    url: str,
    category: str,
    city: str,
) -> Optional[Dict[str, Any]]:
    """
    Mở URL địa điểm và bóc tách đầy đủ dữ liệu để nhét trọn vẹn vào:
    1. places
    2. restaurant_details
    3. hotel_details
    4. place_images
    5. opening_hours
    """
    try:
        await page.goto(url, timeout=45000, wait_until="domcontentloaded")
    except PlaywrightTimeoutError:
        print(f"[!] Timeout khi truy cập chi tiết: {url}")
        return None
    except Exception as e:
        print(f"[!] Lỗi khi truy cập {url}: {e}")
        return None

    try:
        await page.wait_for_selector(SELECTORS["main_pane"], timeout=10000)
    except Exception:
        pass

    current_url = page.url or url
    latitude, longitude = extract_coordinates_from_url(current_url)

    # 1. Tên địa điểm
    name: str = ""
    try:
        h1_elem = page.locator(SELECTORS["name"]).first
        if await h1_elem.is_visible(timeout=3000):
            name = (await h1_elem.inner_text()).strip()
    except Exception:
        name = ""

    if not name:
        return None

    # 2. Không bóc tách đánh giá sao & lượt review (Mặc định None / null)
    rating: Optional[float] = None
    user_ratings_total: Optional[int] = None

    # 4. Địa chỉ
    address: str = ""
    try:
        addr_elem = page.locator(SELECTORS["button_address"]).first
        if await addr_elem.is_visible(timeout=1500):
            raw_addr = (await addr_elem.inner_text()).strip()
            address = re.sub(r"^Địa chỉ:\s*", "", raw_addr, flags=re.IGNORECASE).strip()
            address = address.replace("", "").strip()
    except Exception:
        address = ""

    district = extract_district(address)

    # 5. Số điện thoại
    phone: str = ""
    try:
        phone_elem = page.locator(SELECTORS["button_phone"]).first
        if await phone_elem.is_visible(timeout=1500):
            raw_phone = (await phone_elem.inner_text()).strip()
            phone = re.sub(r"^Số điện thoại:\s*", "", raw_phone, flags=re.IGNORECASE).strip()
            phone = phone.replace("", "").strip()
    except Exception:
        phone = ""

    # 6. Website (Dành cho hotel_details)
    website: str = ""
    try:
        web_elem = page.locator("a[data-item-id='authority']").first
        if await web_elem.is_visible(timeout=1200):
            website = (await web_elem.get_attribute("href") or "").strip()
    except Exception:
        website = ""

    # 7. Giờ hoạt động (Opening Hours)
    opening_hours: str = ""
    try:
        hours_elem = page.locator(SELECTORS["button_opening_hours"]).first
        if await hours_elem.is_visible(timeout=1500):
            raw_hours = (await hours_elem.inner_text()).strip()
            lines = [l.strip() for l in raw_hours.splitlines() if l.strip()]
            opening_hours = " - ".join(lines)
    except Exception:
        opening_hours = ""

    schedule_list = parse_schedule_days(opening_hours)

    # 8. Hình ảnh địa điểm (place_images): Lấy tối thiểu 2 bức ảnh
    images_list: List[str] = []
    try:
        # Quét tất cả thẻ img từ Google CDN trong khu vực nội dung chính
        img_elements = await page.locator("div[role='main'] img[src*='googleusercontent']").all()
        for img in img_elements:
            src = await img.get_attribute("src")
            if src and "http" in src:
                # Nâng cấp chất lượng ảnh lên chuẩn HD w1200-h800
                high_res_url = re.sub(r"=w\d+-h\d+[^=]*", "=w1200-h800-k-no", src)
                if high_res_url not in images_list:
                    images_list.append(high_res_url)
                if len(images_list) >= 2:
                    break
    except Exception:
        pass

    # 9. Thể loại phụ & Mức giá (Dành cho restaurant_details / hotel_details)
    cuisine_type: str = "Ẩm thực & Đồ uống"
    price_range: str = "Vừa phải"
    star_rating: int = 3

    try:
        cat_btn = page.locator(SELECTORS["category_btn"]).first
        if await cat_btn.is_visible(timeout=1000):
            cat_txt = (await cat_btn.inner_text()).strip()
            if cat_txt:
                cuisine_type = cat_txt
    except Exception:
        pass

    try:
        # Mức giá: $, $$, $$$
        price_elem = page.locator("span[aria-label*='Giá:']").first
        if await price_elem.is_visible(timeout=800):
            aria_p = await price_elem.get_attribute("aria-label") or ""
            if "₫₫₫" in aria_p or "$$$" in aria_p:
                price_range = "Cao cấp"
            elif "₫₫" in aria_p or "$$" in aria_p:
                price_range = "Trung bình"
            elif "₫" in aria_p or "$" in aria_p:
                price_range = "Bình dân"
    except Exception:
        pass

    # Phỏng đoán hạng sao khách sạn từ tên hoặc category (ví dụ: 'Khách sạn 4 sao')
    if "5 sao" in name.lower() or "5-star" in name.lower():
        star_rating = 5
    elif "4 sao" in name.lower() or "4-star" in name.lower():
        star_rating = 4
    elif "resort" in name.lower():
        star_rating = 4

    # 10. Tạo Description sạch, không có rating/review
    cat_vn = {
        "nature": "Điểm tham quan thiên nhiên và cảnh quan",
        "culture": "Điểm văn hóa và lịch sử",
        "food": "Địa điểm ẩm thực, nhà hàng, quán ăn",
        "cafe": "Quán cà phê, đồ uống",
        "entertainment": "Khu vui chơi và giải trí",
        "shopping": "Địa điểm mua sắm, chợ",
        "hotel": "Địa điểm lưu trú, khách sạn, nghỉ dưỡng",
        "activity": "Địa điểm trải nghiệm và hoạt động",
        "wellness": "Địa điểm thư giãn và chăm sóc sức khỏe",
        "transport": "Địa điểm giao thông",
        "tour_service": "Dịch vụ du lịch",
        "public_utility": "Tiện ích công cộng",
        "medical": "Cơ sở y tế",
    }.get(category, "Địa điểm du lịch và dịch vụ")

    desc_parts = [f"{name} là {cat_vn.lower()} tọa lạc tại {address or city}."]
    if opening_hours:
        desc_parts.append(f"Thời gian hoạt động: {opening_hours}.")
    if phone:
        desc_parts.append(f"Liên hệ: {phone}.")

    desc_str = " ".join(desc_parts)

    # Chuẩn hóa title: Chỉ lấy tên gốc nguyên bản, cắt bỏ đuôi '- Đà Nẵng', '| Đà Nẵng' nếu có
    clean_title = re.sub(r"[\s\-_|,]+\s*Đà Nẵng$", "", name, flags=re.IGNORECASE).strip()

    record: Dict[str, Any] = {
        "title": clean_title,
        "category": category,
        "city": city,
        "district": district or "",
        "url": current_url,
        "description": desc_str,
        "structured_data": {
            "name": name,
            "address": address,
            "latitude": latitude,
            "longitude": longitude,
            "rating": rating,
            "user_ratings_total": user_ratings_total,
            "phone": phone,
            "website": website,
            "opening_hours": opening_hours,
            "category": category,
            "cuisine_type": cuisine_type,
            "price_range": price_range,
            "star_rating": star_rating,
        },
        "images": images_list,
        "schedules": schedule_list,
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source_type": "google_maps",
    }

    return record
