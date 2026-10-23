"""
Script: normalize_osm_hotels.py
Description: Reads raw Overpass hotel JSON (data/osm_hotels_raw.json), validates and normalizes
             each hotel element into a standardized schema, rejects invalid records (missing name
             or coordinates), deduplicates by (osm_type, osm_id), and saves normalized output to
             data/osm_hotels_normalized.json.

Usage:
    uv run python scripts/normalize_osm_hotels.py
    # or with custom options:
    uv run python scripts/normalize_osm_hotels.py --input data/osm_hotels_raw.json --output data/osm_hotels_normalized.json
"""

import argparse
import json
import logging
import os
from pathlib import Path
import sys
from typing import Any

# Add project root (apps/api) to sys.path
api_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(api_root))

from app.services.osm_hotel_service import OSMHotelService

# Force UTF-8 on Windows stdout if possible
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("normalize_osm_hotels")

DEFAULT_INPUT_FILE = api_root / "data" / "osm_hotels_raw.json"
DEFAULT_OUTPUT_FILE = api_root / "data" / "osm_hotels_normalized.json"


def save_atomic_json(data: Any, output_path: Path) -> None:
    """Save data to output_path atomically via a temporary file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_suffix(f"{output_path.suffix}.tmp")

    try:
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(temp_path, output_path)
    finally:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


def print_report(
    input_file: Path,
    output_file: Path,
    stats: dict[str, Any],
    sample_records: list[dict[str, Any]],
) -> None:
    """Print formatted statistics and 5 sample normalized hotel records."""
    total = stats["total_input"]
    valid = stats["valid_count"]
    discarded = stats["discarded_count"]
    duplicates = stats.get("duplicate_count", 0)
    rejection_breakdown = stats.get("rejection_breakdown", {})
    attrs = stats["attributes"]

    valid_pct = (valid / total * 100) if total > 0 else 0.0
    discarded_pct = (discarded / total * 100) if total > 0 else 0.0

    print("\n========================================================")
    print("📊 BÁO CÁO CHUẨN HÓA DỮ LIỆU KHÁCH SẠN (OPENSTREETMAP)")
    print(f"📥 File đầu vào : {input_file.resolve()}")
    print(f"📤 File đầu ra  : {output_file.resolve()}")
    print("--------------------------------------------------------")
    print(f"🔢 Tổng số bản ghi đầu vào : {total}")
    print(f"✅ Số bản ghi hợp lệ       : {valid} ({valid_pct:.1f}%)")
    print(f"❌ Số bản ghi không hợp lệ : {discarded} ({discarded_pct:.1f}%)")
    print(f"🔄 Số bản ghi trùng lặp    : {duplicates}")

    if rejection_breakdown:
        print("\n⚠️  Phân loại lý do bị loại:")
        for reason, count in rejection_breakdown.items():
            print(f"   • {reason}: {count} bản ghi")

    print("\n📈 Thống kê các thuộc tính trong bản ghi hợp lệ:")
    print(f"   • Có hạng sao (star_rating)  : {attrs['with_star_rating']}/{valid} ({(attrs['with_star_rating']/valid*100):.1f}%)" if valid else "   • Có hạng sao: 0")
    print(f"   • Có địa chỉ (address)       : {attrs['with_address']}/{valid} ({(attrs['with_address']/valid*100):.1f}%)" if valid else "   • Có địa chỉ: 0")
    print(f"   • Có tiện nghi (amenities)   : {attrs['with_amenities']}/{valid} ({(attrs['with_amenities']/valid*100):.1f}%)" if valid else "   • Có tiện nghi: 0")
    print(f"   • Có số phòng (rooms)        : {attrs['with_rooms']}/{valid} ({(attrs['with_rooms']/valid*100):.1f}%)" if valid else "   • Có số phòng: 0")
    print(f"   • Có website                 : {attrs['with_website']}/{valid} ({(attrs['with_website']/valid*100):.1f}%)" if valid else "   • Có website: 0")
    print(f"   • Có số điện thoại (phone)   : {attrs['with_phone']}/{valid} ({(attrs['with_phone']/valid*100):.1f}%)" if valid else "   • Có số điện thoại: 0")
    print(f"   • Có email                   : {attrs['with_email']}/{valid} ({(attrs['with_email']/valid*100):.1f}%)" if valid else "   • Có email: 0")
    print(f"   • Có ảnh (image_url/commons) : {attrs['with_image']}/{valid} ({(attrs['with_image']/valid*100):.1f}%)" if valid else "   • Có ảnh: 0")

    print("\n🔍 5 Bản Ghi Đầu Ra Mẫu:")
    for idx, r in enumerate(sample_records[:5], 1):
        stars_str = f"{r.get('star_rating')} sao" if r.get("star_rating") else "<None>"
        amenities_str = ", ".join(r.get("amenities", [])) or "<None>"
        rooms_str = str(r.get("rooms")) if r.get("rooms") else "<None>"

        print(f"\n  {idx}. [{r.get('osm_type', '').upper()}] ID: {r.get('osm_id')}")
        print(f"     Tên         : {r.get('name')}")
        print(f"     Tọa độ      : lat={r.get('latitude')}, lon={r.get('longitude')}")
        print(f"     Hạng sao    : {stars_str} | Số phòng: {rooms_str}")
        print(f"     Địa chỉ     : {r.get('address') or '<None>'}")
        print(f"     Website     : {r.get('website') or '<None>'}")
        print(f"     Tiện nghi   : {amenities_str}")
        print(f"     Ảnh URL     : {r.get('image_url') or '<None>'}")

    print("========================================================\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate and normalize OpenStreetMap raw hotel data."
    )
    parser.add_argument(
        "--input",
        "-i",
        type=str,
        default=str(DEFAULT_INPUT_FILE),
        help=f"Input raw JSON file path (default: {DEFAULT_INPUT_FILE})",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default=str(DEFAULT_OUTPUT_FILE),
        help=f"Output normalized JSON file path (default: {DEFAULT_OUTPUT_FILE})",
    )
    parser.add_argument(
        "--limit",
        "-l",
        type=int,
        default=None,
        help="Limit number of records to process (for debugging)",
    )

    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()

    if not input_path.exists():
        print(
            f"❌ Input file not found: {input_path}\n"
            f"Vui lòng chạy lệnh sau trước:\n"
            f"    uv run python scripts/fetch_osm_hotels.py",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"📖 Đang đọc dữ liệu từ {input_path}...")
    try:
        with open(input_path, "r", encoding="utf-8") as f:
            raw_data = json.load(f)
    except Exception as exc:
        print(f"❌ Không thể đọc file JSON đầu vào: {exc}", file=sys.stderr)
        sys.exit(1)

    elements: list[dict[str, Any]] = raw_data.get("elements", [])
    if not isinstance(elements, list):
        print("❌ Cấu trúc JSON không hợp lệ: Thiếu mảng 'elements'", file=sys.stderr)
        sys.exit(1)

    if args.limit and args.limit > 0:
        elements = elements[: args.limit]

    print(f"⚙️  Đang chuẩn hóa {len(elements)} bản ghi khách sạn...")
    valid_records, discarded_records, stats = OSMHotelService.normalize_elements(elements)

    print(f"💾 Đang lưu {len(valid_records)} bản ghi chuẩn hóa vào {output_path.name}...")
    save_atomic_json(valid_records, output_path)
    print("✅ Lưu file normalized thành công.")

    print_report(input_path, output_path, stats, valid_records[:5])


if __name__ == "__main__":
    main()
