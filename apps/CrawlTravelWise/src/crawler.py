from __future__ import annotations

import asyncio
import logging
import random
import urllib.parse
from typing import List, Set, Dict, Any

from playwright.async_api import (
    async_playwright,
    Browser,
    BrowserContext,
    Page,
)
from playwright_stealth import stealth_async

from src.config_loader import AppConfig
from src.parser import GoogleMapsParser
from src.pipeline import DataPipeline

logger = logging.getLogger("PlaywrightCrawler")


class GoogleMapsCrawler:
    """
    Crawler Playwright thực thi 2 bước chuyên sâu:
    - Bước 1: Điều hướng đến kết quả tìm kiếm với tâm Đà Nẵng, cuộn danh sách kết quả (Feed) để thu thập tất cả URL & CID.
    - Bước 2: Duyệt từng địa điểm trong danh sách (hỗ trợ concurrency qua tab/worker), bóc tách chi tiết thông tin và đẩy qua Pipeline.
    """

    def __init__(self, config: AppConfig, pipeline: DataPipeline):
        self.config = config
        self.target = config.target
        self.scraper_cfg = config.scraper
        self.pipeline = pipeline

    async def _random_delay(self) -> None:
        """Thực hiện độ trễ ngẫu nhiên mô phỏng hành vi người dùng."""
        delay = random.uniform(self.scraper_cfg.min_delay, self.scraper_cfg.max_delay)
        await asyncio.sleep(delay)

    async def _init_context(self, browser: Browser) -> BrowserContext:
        """Khởi tạo browser context với thiết lập ngôn ngữ và geolocation Đà Nẵng."""
        context = await browser.new_context(
            viewport={"width": 1440, "height": 900},
            locale=f"{self.target.hl}-{self.target.gl}",
            geolocation={"latitude": self.target.center_lat, "longitude": self.target.center_lng},
            permissions=["geolocation"],
            user_agent=self.scraper_cfg.user_agent,
        )
        return context

    async def crawl_keyword_listing(self, page: Page, keyword: str) -> List[str]:
        """
        Bước 1: Tìm kiếm từ khóa và cuộn feed danh sách kết quả để lấy URLs các địa điểm.
        """
        encoded_kw = urllib.parse.quote_plus(keyword)
        # Sử dụng tham số @lat,lng,zoomz và hl=vi để ghim trực tiếp bản đồ tại Đà Nẵng
        search_url = (
            f"https://www.google.com/maps/search/{encoded_kw}/"
            f"@{self.target.center_lat},{self.target.center_lng},{self.target.zoom_level}z"
            f"?hl={self.target.hl}&gl={self.target.gl}"
        )

        logger.info(f"[{keyword}] Bắt đầu tìm kiếm: {search_url}")
        await page.goto(search_url, timeout=self.scraper_cfg.navigation_timeout, wait_until="domcontentloaded")
        await self._random_delay()

        # Kiểm tra nếu Google Maps chuyển thẳng vào chi tiết của 1 địa điểm duy nhất
        if "/maps/place/" in page.url:
            logger.info(f"[{keyword}] Điều hướng trực tiếp đến 1 địa điểm duy nhất: {page.url}")
            return [page.url]

        # Container danh sách kết quả Google Maps thường có aria-label là Kết quả cho... hoặc role='feed'
        feed_selector = "div[role='feed']"
        try:
            await page.wait_for_selector(feed_selector, timeout=12000)
        except Exception:
            logger.warning(f"[{keyword}] Không tìm thấy container role='feed', kiểm tra danh sách kết quả thay thế...")

        collected_urls: Set[str] = set()
        scroll_attempts = 0
        max_scroll_attempts = 25
        last_item_count = 0

        while len(collected_urls) < self.scraper_cfg.max_results and scroll_attempts < max_scroll_attempts:
            # Thu thập các thẻ <a> dẫn đến địa điểm (/maps/place/)
            links = await page.locator("div[role='feed'] a[href*='/maps/place/'], a.hfpxzc").all()
            for link in links:
                try:
                    href = await link.get_attribute("href")
                    if href and "/maps/place/" in href:
                        collected_urls.add(href)
                        if len(collected_urls) >= self.scraper_cfg.max_results:
                            break
                except Exception:
                    continue

            logger.info(f"[{keyword}] Đang cuộn... Thu thập được {len(collected_urls)}/{self.scraper_cfg.max_results} link.")

            if len(collected_urls) >= self.scraper_cfg.max_results:
                break

            # Kiểm tra xem đã chạm đáy danh sách chưa (Google hiển thị text "Bạn đã xem hết kết quả")
            end_indicator = page.locator("span:has-text('Bạn đã xem hết danh sách'), span:has-text('You\\'ve reached the end of the list')")
            if await end_indicator.count() > 0 and await end_indicator.first.is_visible():
                logger.info(f"[{keyword}] Đã chạm đáy danh sách kết quả.")
                break

            # Cuộn thanh cuộn của container kết quả xuống dưới
            feed_elem = page.locator(feed_selector)
            if await feed_elem.count() > 0:
                await feed_elem.evaluate("node => node.scrollBy(0, 1500)")
            else:
                await page.mouse.wheel(0, 1200)

            await self._random_delay()

            # Nếu số lượng link không thay đổi sau 3 lần cuộn liên tiếp
            if len(collected_urls) == last_item_count:
                scroll_attempts += 1
            else:
                scroll_attempts = 0
                last_item_count = len(collected_urls)

        result_list = list(collected_urls)[:self.scraper_cfg.max_results]
        logger.info(f"[{keyword}] Hoàn tất Bước 1: Lấy được {len(result_list)} địa điểm cần cào.")
        return result_list

    async def crawl_place_details_worker(
        self,
        context: BrowserContext,
        urls: List[str],
        keyword: str
    ) -> None:
        """
        Bước 2: Mở từng URL để bóc tách thông tin chi tiết và đẩy qua data pipeline.
        """
        page = await context.new_page()
        await stealth_async(page)
        page.set_default_timeout(self.scraper_cfg.action_timeout)

        try:
            for idx, url in enumerate(urls, start=1):
                try:
                    logger.info(f"[{keyword}] ({idx}/{len(urls)}) Đang cào chi tiết: {url}")
                    await page.goto(url, timeout=self.scraper_cfg.navigation_timeout, wait_until="domcontentloaded")
                    await self._random_delay()

                    # Đợi một chút để các button thông tin địa chỉ hiển thị hoàn chỉnh
                    await page.wait_for_selector("div[role='main']", timeout=8000)

                    # Bóc tách dữ liệu
                    raw_data = await GoogleMapsParser.parse_place_detail(page, fallback_url=url)

                    # Đưa vào Pipeline làm sạch, validate và lưu trữ
                    record = self.pipeline.process_item(raw_data, search_keyword=keyword)
                    if record:
                        self.pipeline.save_record(record)
                        logger.info(f"  -> Lưu thành công: {record.name} | Quận: {record.district or 'N/A'}")
                    else:
                        logger.debug("  -> Bỏ qua hoặc dữ liệu không hợp lệ.")

                except Exception as ex:
                    logger.warning(f"Lỗi khi cào URL {url}: {ex}")
                    continue
        finally:
            await page.close()

    async def run(self) -> None:
        """Điều phối toàn bộ quy trình cào."""
        logger.info("Khởi động Playwright...")
        async with async_playwright() as p:
            browser_launcher = getattr(p, self.scraper_cfg.browser_type)
            browser = await browser_launcher.launch(
                headless=self.scraper_cfg.headless,
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                ]
            )

            context = await self._init_context(browser)
            search_page = await context.new_page()
            await stealth_async(search_page)

            try:
                for kw in self.target.keywords:
                    logger.info(f"\n===== XỬ LÝ TỪ KHÓA: '{kw}' =====")
                    urls = await self.crawl_keyword_listing(search_page, kw)

                    if not urls:
                        logger.warning(f"Không tìm thấy kết quả nào cho từ khóa '{kw}'.")
                        continue

                    # Chia URLs ra theo concurrency để crawl song song qua các tab
                    num_workers = min(self.scraper_cfg.concurrency, len(urls))
                    chunk_size = (len(urls) + num_workers - 1) // num_workers
                    chunks = [urls[i:i + chunk_size] for i in range(0, len(urls), chunk_size)]

                    tasks = [
                        self.crawl_place_details_worker(context, chunk, kw)
                        for chunk in chunks if chunk
                    ]
                    await asyncio.gather(*tasks)

            finally:
                await context.close()
                await browser.close()
                logger.info("Đã đóng trình duyệt Playwright và hoàn tất quy trình.")

