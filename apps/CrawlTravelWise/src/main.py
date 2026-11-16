from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from src.config_loader import load_config
from src.crawler import GoogleMapsCrawler
from src.pipeline import DataPipeline


def setup_logger(log_level: int = logging.INFO) -> None:
    """Cấu hình logging dạng chuẩn Data Engineering có timestamp rõ ràng."""
    log_format = "%(asctime)s [%(levelname)s] [%(name)s] %(message)s"
    date_format = "%Y-%m-%d %H:%M:%S"

    logging.basicConfig(
        level=log_level,
        format=log_format,
        datefmt=date_format,
        handlers=[
            logging.StreamHandler(sys.stdout),
        ]
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Google Maps Data Scraper for Da Nang City using Playwright."
    )
    parser.add_argument(
        "-c", "--config",
        type=str,
        default="config.toml",
        help="Đường dẫn đến file cấu hình TOML (mặc định: config.toml)"
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        default=None,
        help="Bật chế độ headless (ghi đè thiết lập trong config.toml nếu truyền)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Bật chế độ debug log chi tiết"
    )
    return parser.parse_args()


async def main_async() -> None:
    args = parse_args()
    setup_logger(logging.DEBUG if args.debug else logging.INFO)
    logger = logging.getLogger("Main")

    logger.info("Đang nạp file cấu hình...")
    config = load_config(args.config)

    # Nếu truyền flag --headless từ CLI thì override config
    if args.headless is not None:
        config.scraper.headless = args.headless

    logger.info(
        f"Cấu hình đã nạp thành công: {len(config.target.keywords)} từ khóa | "
        f"Headless={config.scraper.headless} | Định dạng={config.storage.format} ({config.storage.write_mode})"
    )

    # 1. Khởi tạo Data Pipeline
    pipeline = DataPipeline(config.storage)

    # 2. Khởi tạo Crawler
    crawler = GoogleMapsCrawler(config=config, pipeline=pipeline)

    # 3. Thực thi cào dữ liệu
    await crawler.run()

    logger.info(f"==> Toàn bộ quá trình hoàn tất! Dữ liệu được lưu tại: {pipeline.output_file.resolve()}")


def run() -> None:
    """Entry point cho command-line script."""
    try:
        asyncio.run(main_async())
    except KeyboardInterrupt:
        print("\n[!] Tiến trình bị dừng bởi người dùng (Ctrl+C).")
        sys.exit(0)
    except Exception as e:
        print(f"\n[X] Đã xảy ra lỗi nghiêm trọng: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    run()

