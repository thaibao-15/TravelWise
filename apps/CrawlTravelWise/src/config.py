"""
Module cấu hình toàn bộ tham số hoạt động của crawler:
- Danh sách từ khóa chuẩn hóa theo 13 Categories trong TravelWiseDB (dòng 472-485)
- DOM Selectors chuẩn bền vững trên Google Maps
- Thiết lập Anti-bot, User-Agent, Delays
"""

from typing import Dict, List, Tuple

# Danh sách từ khóa tìm kiếm ánh xạ chính xác 1-1 với 13 Categories trong TravelWiseDB:
# 1. Thiên nhiên và cảnh quan
# 2. Văn hóa và lịch sử
# 3. Ẩm thực
# 4. Quán cà phê
# 5. Vui chơi và giải trí
# 6. Mua sắm và chợ
# 7. Lưu trú và nghỉ dưỡng
# 8. Trải nghiệm và hoạt động
# 9. Thư giãn và chăm sóc sức khỏe
# 10. Giao thông
# 11. Dịch vụ du lịch
# 12. Tiện ích công cộng
# 13. Y tế

KEYWORDS: Dict[str, List[str]] = {
    # ID = 1: Bãi biển, núi, bán đảo, hồ, thác nước và các điểm ngắm cảnh.
    "nature": [
        "bãi biển đẹp Đà Nẵng",
        "bán đảo Sơn Trà điểm ngắm cảnh Đà Nẵng",
        "đỉnh Bàn Cờ Sơn Trà Đà Nẵng",
        "thác Mơ Hòa Vang Đà Nẵng",
        "hồ Đồng Xanh Đồng Nghệ Đà Nẵng",
        "rạn Nam Ô Đà Nẵng",
    ],
    # ID = 2: Chùa, đền, bảo tàng, di tích lịch sử và làng nghề truyền thống.
    "culture": [
        "chùa nổi tiếng Đà Nẵng",
        "chùa Linh Ứng Đà Nẵng",
        "bảo tàng Đà Nẵng",
        "bảo tàng Điêu khắc Chăm Đà Nẵng",
        "di tích danh thắng Ngũ Hành Sơn Đà Nẵng",
        "làng đá mỹ nghệ Non Nước Đà Nẵng",
    ],
    # ID = 3: Nhà hàng, quán ăn, quán ăn đường phố và địa điểm thưởng thức đặc sản.
    "food": [
        "nhà hàng hải sản Đà Nẵng",
        "nhà hàng view biển Đà Nẵng",
        "nhà hàng sang trọng fine dining Đà Nẵng",
        "nhà hàng đồ nướng BBQ Đà Nẵng",
        "nhà hàng Nhật Bản sushi Đà Nẵng",
        "nhà hàng Hàn Quốc Đà Nẵng",
        "nhà hàng món Âu pizza Đà Nẵng",
        "nhà hàng chay ngon Đà Nẵng",
        "quán ăn đặc sản Đà Nẵng",
        "quán ăn ngon Đà Nẵng",
        "bánh tráng cuốn thịt heo Đà Nẵng",
        "mì quảng ngon Đà Nẵng",
        "bún chả cá Đà Nẵng",
        "bê thui Cầu Mống Đà Nẵng",
        "ẩm thực đường phố chợ đêm Đà Nẵng",
    ],
    # ID = 4: Quán cà phê, trà và các địa điểm thưởng thức đồ uống.
    "cafe": [
        "quán cà phê view biển Đà Nẵng",
        "quán cafe đẹp Hải Châu Đà Nẵng",
        "cafe làm việc yên tĩnh Đà Nẵng",
        "tiệm trà bánh check in Đà Nẵng",
        "quán cafe An Thượng Đà Nẵng",
    ],
    # ID = 5: Công viên giải trí, khu vui chơi, phố đi bộ và địa điểm giải trí.
    "entertainment": [
        "khu vui chơi giải trí Đà Nẵng",
        "Bà Nà Hills Đà Nẵng",
        "công viên Châu Á Asia Park Đà Nẵng",
        "công viên suối khoáng nóng Núi Thần Tài",
        "phố đi bộ Bạch Đằng Đà Nẵng",
    ],
    # ID = 6: Chợ truyền thống, chợ đêm, trung tâm thương mại và cửa hàng đặc sản.
    "shopping": [
        "chợ truyền thống Đà Nẵng",
        "chợ Hàn Đà Nẵng",
        "chợ Cồn Đà Nẵng",
        "chợ đêm Sơn Trà Đà Nẵng",
        "chợ đêm Helio Đà Nẵng",
        "siêu thị đặc sản Đà Nẵng",
        "Vincom Plaza Đà Nẵng",
    ],
    # ID = 7: Khách sạn, resort, homestay và căn hộ du lịch.
    "hotel": [
        "khách sạn ven biển Đà Nẵng",
        "resort nghỉ dưỡng Đà Nẵng",
        "homestay đẹp Đà Nẵng",
        "khách sạn 4 sao 5 sao Đà Nẵng",
        "căn hộ du lịch gần biển Đà Nẵng",
    ],
    # ID = 8: Leo núi, lặn biển, chèo kayak, cắm trại và các hoạt động du lịch.
    "activity": [
        "chèo sup chèo kayak Đà Nẵng",
        "tour lặn ngắm san hô Sơn Trà Đà Nẵng",
        "địa điểm cắm trại camping Đà Nẵng",
        "dù lượn Sơn Trà Đà Nẵng",
    ],
    # ID = 9: Spa, massage, suối khoáng nóng và khu nghỉ dưỡng sức khỏe.
    "wellness": [
        "spa massage thư giãn Đà Nẵng",
        "tiệm massage chân bấm huyệt Đà Nẵng",
        "xông hơi thảo dược spa Đà Nẵng",
    ],
    # ID = 10: Sân bay, ga tàu, bến xe và bến tàu du lịch.
    "transport": [
        "sân bay quốc tế Đà Nẵng",
        "ga Đà Nẵng",
        "bến xe trung tâm Đà Nẵng",
        "bến du thuyền sông Hàn Đà Nẵng",
    ],
    # ID = 11: Điểm thuê xe, bán vé, đặt tour và trung tâm thông tin du lịch.
    "tour_service": [
        "cho thuê xe máy Đà Nẵng",
        "thuê xe tự lái Đà Nẵng",
        "công ty du lịch đặt tour Đà Nẵng",
    ],
    # ID = 12: Bãi đỗ xe, nhà vệ sinh công cộng, ATM và các tiện ích thiết yếu.
    "public_utility": [
        "bãi giữ xe công cộng Đà Nẵng",
        "cây ATM ngân hàng trung tâm Đà Nẵng",
    ],
    # ID = 13: Bệnh viện, phòng khám và nhà thuốc phục vụ khách du lịch.
    "medical": [
        "bệnh viện quốc tế Vinmec Đà Nẵng",
        "bệnh viện Đà Nẵng",
        "phòng khám đa khoa Đà Nẵng",
        "nhà thuốc lớn Đà Nẵng",
    ],
}

# Cấu hình Selectors DOM của Google Maps
SELECTORS: Dict[str, str] = {
    "feed": "div[role='feed']",
    "place_link": "a[href*='/maps/place/']",
    "end_of_list_vi": "span:has-text('Bạn đã xem hết kết quả')",
    "end_of_list_vi_alt": "span:has-text('Bạn đã xem hết danh sách')",
    "end_of_list_en": "span:has-text(\"You've reached the end of the list\")",
    "name": "h1",
    "rating_stars": "span.ceNzKf",
    "rating_value": "div.F7nice span[aria-hidden='true']",
    "review_count": "div.F7nice span > span[aria-label]",
    "button_address": "button[data-item-id='address']",
    "button_phone": "button[data-item-id^='phone:']",
    "button_opening_hours": "button[data-item-id*='oh'], div[data-item-id*='oh']",
    "category_btn": "button[jsaction*='pane.rating.category']",
    "main_pane": "div[role='main']",
}

# Cấu hình Anti-bot Chromium
CHROMIUM_ARGS: List[str] = [
    "--disable-blink-features=AutomationControlled",
    "--lang=vi-VN,vi",
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-infobars",
    "--window-position=0,0",
    "--ignore-certificate-errors",
]

# User-Agent chuẩn
USER_AGENT: str = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

# Khoảng thời gian nghỉ ngẫu nhiên (giây)
RANDOM_DELAY_RANGE: Tuple[float, float] = (1.5, 3.2)

# Danh sách quận / huyện tại Đà Nẵng
DANANG_DISTRICTS: List[str] = [
    "Hải Châu",
    "Sơn Trà",
    "Ngũ Hành Sơn",
    "Thanh Khê",
    "Liên Chiểu",
    "Cẩm Lệ",
    "Hòa Vang",
    "Hoàng Sa",
]
