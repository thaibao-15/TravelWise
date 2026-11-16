"""
File thực thi chính (Entrypoint CLI) cho crawler Google Maps:
- Tự động kết nối và import trực tiếp vào SQL Server (TravelWiseDB)
- Tự động khử trùng lặp qua Tên và Tọa độ GPS (STDistance <= 25m)
- Ghi kèm file backup JSONL trong thư mục data/
"""

import argparse
import asyncio
from pathlib import Path
import sys
from typing import Dict, List, Set

from playwright.async_api import async_playwright
from tqdm.asyncio import tqdm

from src.config import CHROMIUM_ARGS, KEYWORDS, USER_AGENT
from src.extractor import extract_place_details
from src.scroller import random_sleep, scroll_and_collect_urls
from src.storage import (
    get_category_id_map,
    get_sqlserver_connection,
    insert_place_to_sqlserver,
    load_existing_names_and_locations,
    load_existing_urls_from_jsonl,
    save_backup_jsonl,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Google Maps Crawler - Tự động cào và nạp vào cơ sở dữ liệu SQL Server (TravelWiseDB)."
    )
    parser.add_argument(
        "--category",
        type=str,
        default="food",
        choices=[
            "nature",
            "culture",
            "food",
            "cafe",
            "entertainment",
            "shopping",
            "hotel",
            "activity",
            "wellness",
            "transport",
            "tour_service",
            "public_utility",
            "medical",
            "all",
        ],
        help="Danh mục theo TravelWiseDB (nature, culture, food, cafe, entertainment, shopping, hotel, activity, wellness, transport, tour_service, public_utility, medical, hoặc all). Mặc định: food",
    )
    parser.add_argument(
        "--city",
        type=str,
        default="Đà Nẵng",
        help="Tên thành phố tìm kiếm (Mặc định: 'Đà Nẵng')",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Số lượng địa điểm mục tiêu cho mỗi từ khóa (Mặc định: 20)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="crawled_places.jsonl",
        help="Tên file backup kết quả trong thư mục data/ (Mặc định: crawled_places.jsonl)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        default=False,
        help="Chạy ngầm không hiện cửa sổ trình duyệt. Mặc định: False",
    )
    return parser.parse_args()


async def run_crawler() -> None:
    args = parse_arguments()
    backup_file = Path("data") / args.output

    if args.category == "all":
        categories_to_run = list(KEYWORDS.keys())
    else:
        categories_to_run = [args.category]

    print("=" * 65)
    print("🚀 GOOGLE MAPS CRAWLER -> TỰ ĐỘNG IMPORT VÀO TRAVELWISEDB")
    print(f"📍 Thành phố: {args.city}")
    print(f"📂 Danh mục: {', '.join(categories_to_run)}")
    print(f"🎯 Giới hạn mỗi từ khóa: {args.limit} địa điểm")
    print(f"🖥️ Chế độ Headless: {args.headless}")
    print("=" * 65)

    # 1. Kết nối SQL Server
    db_conn = get_sqlserver_connection()
    cat_id_map: Dict[str, int] = {}
    if db_conn:
        print("[+] Kết nối SQL Server TravelWiseDB thành công!")
        cursor = db_conn.cursor()
        cat_id_map = get_category_id_map(cursor)
    else:
        print("[!] Không có kết nối DB. Dữ liệu sẽ chỉ lưu vào file backup JSONL.")

    # 2. Tải danh sách URLs và Tên địa điểm đã có để chống trùng lặp
    existing_urls: Set[str] = load_existing_urls_from_jsonl(backup_file)
    existing_names: Set[str] = load_existing_names_and_locations(db_conn)
    print(f"[*] Đã tải {len(existing_urls)} URLs và {len(existing_names)} địa điểm hiện có để chống trùng lặp.\n")

    total_scraped = 0
    total_db_inserted = 0

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=args.headless,
            args=CHROMIUM_ARGS,
        )

        context = await browser.new_context(
            user_agent=USER_AGENT,
            viewport={"width": 1440, "height": 900},
            locale="vi-VN",
            timezone_id="Asia/Ho_Chi_Minh",
        )

        scroll_page = await context.new_page()
        detail_page = await context.new_page()

        try:
            for cat in categories_to_run:
                keywords_list = KEYWORDS.get(cat, [])
                print(f"\n==================== DANH MỤC: {cat.upper()} ({len(keywords_list)} từ khóa) ====================")

                for kw in keywords_list:
                    full_keyword = f"{kw} {args.city}" if args.city not in kw else kw

                    new_urls = await scroll_and_collect_urls(
                        page=scroll_page,
                        keyword=full_keyword,
                        target_count=args.limit,
                        existing_urls=existing_urls,
                    )

                    if not new_urls:
                        print(f"[-] Không có URL mới nào cho từ khóa: '{full_keyword}'. Chuyển tiếp...")
                        continue

                    print(f"[*] Bắt đầu bóc tách & import cho {len(new_urls)} địa điểm mới:")

                    with tqdm(total=len(new_urls), desc=f"Trích xuất [{kw[:20]}]", unit="place") as pbar:
                        for place_url in new_urls:
                            record = await extract_place_details(
                                page=detail_page,
                                url=place_url,
                                category=cat,
                                city=args.city,
                            )

                            if record:
                                name_check = record["structured_data"]["name"].strip().lower()
                                if name_check in existing_names:
                                    pbar.set_postfix_str(f"Đã có trong DB: {name_check[:15]}")
                                    pbar.update(1)
                                    continue

                                # 1. Lưu backup JSONL
                                save_backup_jsonl(backup_file, record)
                                existing_urls.add(place_url)
                                total_scraped += 1

                                # 2. Tự động Import trực tiếp vào SQL Server TravelWiseDB
                                if db_conn:
                                    success = insert_place_to_sqlserver(db_conn, record, cat_id_map)
                                    if success:
                                        total_db_inserted += 1
                                        existing_names.add(name_check)
                                        pbar.set_postfix_str(f"Đã vào DB: {record['structured_data']['name'][:16]}")
                                    else:
                                        pbar.set_postfix_str("Trùng GPS/Tên trong DB")
                                else:
                                    pbar.set_postfix_str("Đã lưu JSONL")
                            else:
                                pbar.set_postfix_str("Lỗi trích xuất")

                            pbar.update(1)
                            await random_sleep(1.0, 2.0)

        except Exception as e:
            print(f"\n[X] Lỗi: {e}", file=sys.stderr)
        finally:
            if db_conn:
                db_conn.close()
            await scroll_page.close()
            await detail_page.close()
            await context.close()
            await browser.close()

    print("\n" + "=" * 65)
    print("🎉 HOÀN THÀNH QUY TRÌNH!")
    print(f"📊 Tổng số địa điểm cào được: {total_scraped}")
    print(f"💾 Số địa điểm mới import thành công vào SQL Server (TravelWiseDB): {total_db_inserted}")
    print(f"📁 File backup: {backup_file.resolve()}")
    print("=" * 65)


def main() -> None:
    try:
        asyncio.run(run_crawler())
    except KeyboardInterrupt:
        print("\n[!] Dừng chương trình. Dữ liệu đã lưu an toàn.")
        sys.exit(0)


if __name__ == "__main__":
    main()
