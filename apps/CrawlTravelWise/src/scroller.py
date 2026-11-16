"""
Module điều khiển Playwright để cuộn container feed và gom danh sách URL địa điểm.
"""

import asyncio
import random
import re
import urllib.parse
from typing import List, Set
from playwright.async_api import Page, TimeoutError as PlaywrightTimeoutError

from src.config import RANDOM_DELAY_RANGE, SELECTORS


def clean_gmaps_url(raw_url: str) -> str:
    """
    Chuẩn hóa URL của Google Maps:
    Loại bỏ các query parameter thừa như ?authuser=0, ?entry=ttu,...
    giữ lại cấu trúc sạch https://www.google.com/maps/place/...
    """
    if not raw_url:
        return ""
    # Cắt bỏ phần query string bắt đầu bằng ?
    cleaned = raw_url.split("?")[0]
    return cleaned.strip()


async def random_sleep(min_sec: float | None = None, max_sec: float | None = None) -> None:
    """Nghỉ ngẫu nhiên giữa các thao tác để tránh anti-bot fingerprinting."""
    lower = min_sec if min_sec is not None else RANDOM_DELAY_RANGE[0]
    upper = max_sec if max_sec is not None else RANDOM_DELAY_RANGE[1]
    await asyncio.sleep(random.uniform(lower, upper))


async def scroll_and_collect_urls(
    page: Page,
    keyword: str,
    target_count: int,
    existing_urls: Set[str],
) -> List[str]:
    """
    Tìm kiếm từ khóa trên Google Maps, cuộn feed container và gom danh sách URLs mới.

    Args:
        page: Playwright Page đang hoạt động
        keyword: Từ khóa tìm kiếm (ví dụ: 'nhà hàng hải sản Đà Nẵng')
        target_count: Số lượng URL mới tối đa cần thu thập cho từ khóa này
        existing_urls: Tập hợp URLs đã có từ trước để khử trùng lặp tức thì

    Returns:
        Danh sách URL địa điểm mới chưa từng cào
    """
    encoded_kw = urllib.parse.quote_plus(keyword)
    search_url = f"https://www.google.com/maps/search/{encoded_kw}/?hl=vi&gl=VN"

    print(f"\n[*] Đang tìm kiếm: {keyword} -> {search_url}")
    try:
        await page.goto(search_url, timeout=60000, wait_until="domcontentloaded")
    except PlaywrightTimeoutError:
        print(f"[!] Timeout khi tải trang tìm kiếm cho từ khóa: '{keyword}'")
        return []

    await random_sleep()

    # Kiểm tra trường hợp Google Maps chuyển thẳng tới 1 địa điểm duy nhất
    current_url = page.url
    if "/maps/place/" in current_url:
        cleaned = clean_gmaps_url(current_url)
        if cleaned not in existing_urls:
            print(f"[+] Tìm thấy địa điểm duy nhất chuyển hướng: {cleaned}")
            return [cleaned]
        return []

    # Chờ container div[role="feed"] xuất hiện
    feed_selector = SELECTORS["feed"]
    try:
        await page.wait_for_selector(feed_selector, timeout=15000)
    except PlaywrightTimeoutError:
        print(f"[!] Không tìm thấy container feed (`{feed_selector}`) cho từ khóa: '{keyword}'")
        return []

    collected_urls: List[str] = []
    seen_in_session: Set[str] = set()

    consecutive_no_increase = 0
    max_no_increase_threshold = 5

    while len(collected_urls) < target_count:
        # Bóc tách tất cả thẻ a dẫn tới địa điểm
        link_elements = await page.locator(f"{feed_selector} {SELECTORS['place_link']}").all()

        current_batch_count = len(collected_urls)

        for elem in link_elements:
            try:
                href = await elem.get_attribute("href")
                if not href or "/maps/place/" not in href:
                    continue

                clean_url = clean_gmaps_url(href)
                # Bỏ qua nếu đã có trong dữ liệu cũ hoặc đã gom trong phiên này
                if clean_url in existing_urls or clean_url in seen_in_session:
                    continue

                seen_in_session.add(clean_url)
                collected_urls.append(clean_url)

                if len(collected_urls) >= target_count:
                    break
            except Exception:
                continue

        # In tiến độ thu thập
        print(f"  -> Đã gom: {len(collected_urls)}/{target_count} URL mới...", end="\r")

        if len(collected_urls) >= target_count:
            break

        # Kiểm tra thông báo chạm đáy danh sách kết quả
        is_end = False
        for end_selector_key in ["end_of_list_vi", "end_of_list_vi_alt", "end_of_list_en"]:
            end_elem = page.locator(SELECTORS[end_selector_key])
            if await end_elem.count() > 0 and await end_elem.first.is_visible():
                is_end = True
                break

        if is_end:
            print(f"\n[*] Đã chạm đáy danh sách kết quả của Google Maps cho từ khóa: '{keyword}'.")
            break

        # Kiểm tra số lượng có tăng sau lần cuộn này không
        if len(collected_urls) == current_batch_count:
            consecutive_no_increase += 1
            if consecutive_no_increase >= max_no_increase_threshold:
                print(f"\n[*] Số lượng không tăng sau {max_no_increase_threshold} lần cuộn liên tiếp. Dừng cuộn.")
                break
        else:
            consecutive_no_increase = 0

        # Thực thi cuộn container feed xuống đáy qua JS
        try:
            await page.evaluate(
                f"""() => {{
                    const feed = document.querySelector("{feed_selector}");
                    if (feed) {{
                        feed.scrollTop = feed.scrollHeight;
                    }}
                }}"""
            )
        except Exception:
            # Fallback nếu evaluate gặp sự cố
            await page.mouse.wheel(0, 1500)

        await random_sleep()

    print(f"\n[v] Hoàn thành cuộn: Lấy được {len(collected_urls)} URLs mới cho từ khóa '{keyword}'.")
    return collected_urls

