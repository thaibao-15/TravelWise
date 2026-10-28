"""
Script: normalize_osm_restaurants.py
Description: Reads raw Overpass JSON (data/osm_restaurants_raw.json), validates and normalizes
             each restaurant element, filters out invalid records (missing name or coordinates)
             with detailed rejection reasons, and saves normalized output to
             data/osm_restaurants_normalized.json.

Usage:
    uv run python scripts/normalize_osm_restaurants.py
    # or with options:
    uv run python scripts/normalize_osm_restaurants.py --input data/osm_restaurants_raw.json --output data/osm_restaurants_normalized.json
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Optional

# Add project root (apps/api) to sys.path
api_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(api_root))

# Force UTF-8 on Windows stdout if possible
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

from app.schemas.osm_restaurant import NormalizedRestaurant
from app.services.osm_restaurant_service import OSMRestaurantService

DEFAULT_INPUT_FILE = api_root / "data" / "osm_restaurants_raw.json"
DEFAULT_OUTPUT_FILE = api_root / "data" / "osm_restaurants_normalized.json"


class RejectionReason:
    MISSING_NAME = "Missing name"
    MISSING_COORDINATES = "Missing coordinates"
    MISSING_BOTH = "Missing both name and coordinates"
    INVALID_COORDINATES = "Coordinates out of bounds (-90..90, -180..180)"


def evaluate_element(
    element: dict[str, Any],
) -> tuple[Optional[NormalizedRestaurant], Optional[str]]:
    """Evaluate and normalize a single raw OSM element.

    Returns:
        (NormalizedRestaurant, None) if valid.
        (None, rejection_reason) if invalid.

    Rejection criteria:
        1. Missing name (or empty string).
        2. Missing coordinates (or invalid range).
        3. Missing both.
    """
    osm_id = element.get("id")
    osm_type = element.get("type")
    tags = element.get("tags") or {}

    # 1. Name check
    name = OSMRestaurantService.extract_name(tags)
    has_name = bool(name and name.strip())

    # 2. Coordinates check
    lat, lon = OSMRestaurantService.extract_coordinates(element)
    has_coords = lat is not None and lon is not None

    if not has_name and not has_coords:
        return None, RejectionReason.MISSING_BOTH
    if not has_name:
        return None, RejectionReason.MISSING_NAME
    if not has_coords:
        return None, RejectionReason.MISSING_COORDINATES

    # 3. Normalize element
    normalized = OSMRestaurantService.normalize_element(element)
    return normalized, None


def normalize_osm_data(
    raw_data: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    """Process raw Overpass JSON dictionary into normalized records and rejection logs.

    Returns:
        (valid_records, discarded_records, stats)
    """
    elements = raw_data.get("elements", [])
    valid_records: list[dict[str, Any]] = []
    discarded_records: list[dict[str, Any]] = []

    rejection_counts: dict[str, int] = {
        RejectionReason.MISSING_NAME: 0,
        RejectionReason.MISSING_COORDINATES: 0,
        RejectionReason.MISSING_BOTH: 0,
        RejectionReason.INVALID_COORDINATES: 0,
    }

    # Process each element distinctly (never merging records just because names match)
    for el in elements:
        normalized, reason = evaluate_element(el)
        if normalized:
            # Dump Pydantic model to clean JSON-compatible dictionary
            valid_records.append(normalized.model_dump(mode="json"))
        else:
            rejection_counts[reason] = rejection_counts.get(reason, 0) + 1
            discarded_records.append(
                {
                    "osm_type": el.get("type"),
                    "osm_id": el.get("id"),
                    "reason": reason,
                    "tags": el.get("tags") or {},
                }
            )

    # Compute detailed statistics on valid records
    with_cuisine = sum(1 for r in valid_records if r.get("cuisine"))
    with_address = sum(1 for r in valid_records if r.get("address"))
    with_hours = sum(
        1
        for r in valid_records
        if r.get("opening_hours_raw") or (r.get("opening_hours") and len(r["opening_hours"]) > 0)
    )
    with_image = sum(1 for r in valid_records if r.get("image_url"))
    with_phone = sum(1 for r in valid_records if r.get("phone"))
    with_website = sum(1 for r in valid_records if r.get("website"))
    with_vegetarian = sum(1 for r in valid_records if r.get("is_vegetarian") is not None)

    stats = {
        "total_input": len(elements),
        "valid_count": len(valid_records),
        "discarded_count": len(discarded_records),
        "rejection_breakdown": rejection_counts,
        "attributes": {
            "with_cuisine": with_cuisine,
            "with_address": with_address,
            "with_opening_hours": with_hours,
            "with_image_url": with_image,
            "with_phone": with_phone,
            "with_website": with_website,
            "with_vegetarian": with_vegetarian,
        },
    }

    return valid_records, discarded_records, stats


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
    """Print formatting statistics and 5 sample normalized records."""
    total = stats["total_input"]
    valid = stats["valid_count"]
    discarded = stats["discarded_count"]
    attrs = stats["attributes"]
    rejections = stats["rejection_breakdown"]

    print("\n========================================================")
    print("📊 BÁO CÁO CHUẨN HÓA DỮ LIỆU NHÀ HÀNG (OPENSTREETMAP)")
    print(f"📥 File đầu vào : {input_file.resolve()}")
    print(f"📤 File đầu ra  : {output_file.resolve()}")
    print("--------------------------------------------------------")
    print(f"🔢 Tổng số bản ghi đầu vào : {total}")
    print(f"✅ Số bản ghi hợp lệ       : {valid} ({valid/total*100:.1f}%)" if total else "0")
    print(f"❌ Số bản ghi bị loại      : {discarded} ({discarded/total*100:.1f}%)" if total else "0")

    print("\n⚠️  Phân loại lý do bị loại:")
    for reason, count in rejections.items():
        if count > 0:
            print(f"   • {reason}: {count} bản ghi")

    print("\n📈 Thống kê các thuộc tính trong bản ghi hợp lệ:")
    print(f"   • Có thông tin cuisine     : {attrs['with_cuisine']}/{valid} ({attrs['with_cuisine']/valid*100:.1f}%)" if valid else "")
    print(f"   • Có địa chỉ (address)     : {attrs['with_address']}/{valid} ({attrs['with_address']/valid*100:.1f}%)" if valid else "")
    print(f"   • Có giờ mở cửa            : {attrs['with_opening_hours']}/{valid} ({attrs['with_opening_hours']/valid*100:.1f}%)" if valid else "")
    print(f"   • Có URL ảnh (image_url)   : {attrs['with_image_url']}/{valid} ({attrs['with_image_url']/valid*100:.1f}%)" if valid else "")
    print(f"   • Có số điện thoại         : {attrs['with_phone']}/{valid} ({attrs['with_phone']/valid*100:.1f}%)" if valid else "")
    print(f"   • Có website               : {attrs['with_website']}/{valid} ({attrs['with_website']/valid*100:.1f}%)" if valid else "")
    print(f"   • Có cờ ăn chay rõ ràng    : {attrs['with_vegetarian']}/{valid} ({attrs['with_vegetarian']/valid*100:.1f}%)" if valid else "")

    print("\n🔍 5 Bản Ghi Đầu Ra Mẫu:")
    for idx, r in enumerate(sample_records[:5], 1):
        print(f"\n  {idx}. [{r['osm_type'].upper()}] ID: {r['osm_id']}")
        print(f"     Tên         : {r['name']}")
        print(f"     Tọa độ      : lat={r['latitude']}, lon={r['longitude']}")
        print(f"     Địa chỉ     : {r['address'] or '<None>'}")
        print(f"     Cuisine     : {r['cuisine'] or '<None>'}")
        print(f"     Giờ mở cửa  : {r['opening_hours_raw'] or '<None>'}")
        print(f"     Ảnh URL     : {r['image_url'] or '<None>'}")
    print("========================================================\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize raw OpenStreetMap Overpass JSON data for Da Nang restaurants."
    )
    parser.add_argument(
        "--input",
        "-i",
        type=str,
        default=str(DEFAULT_INPUT_FILE),
        help=f"Path to input raw JSON file (default: {DEFAULT_INPUT_FILE})",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default=str(DEFAULT_OUTPUT_FILE),
        help=f"Path to output normalized JSON file (default: {DEFAULT_OUTPUT_FILE})",
    )

    args = parser.parse_args()
    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()

    if not input_path.exists():
        print(
            f"❌ File đầu vào không tồn tại: {input_path}\n"
            f"Vui lòng chạy script thu thập trước:\n"
            f"    uv run python scripts/fetch_osm_restaurants.py",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"📖 Reading raw JSON from {input_path}...")
    try:
        with open(input_path, "r", encoding="utf-8") as f:
            raw_data = json.load(f)
    except Exception as exc:
        print(f"❌ Failed to parse JSON file {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(raw_data, dict) or "elements" not in raw_data:
        print(
            f"❌ File JSON không đúng định dạng Overpass (thiếu trường 'elements')",
            file=sys.stderr,
        )
        sys.exit(1)

    print("⚙️  Normalizing restaurant records...")
    valid_records, discarded_records, stats = normalize_osm_data(raw_data)

    print(f"💾 Saving {len(valid_records)} normalized records to {output_path}...")
    save_atomic_json(valid_records, output_path)
    print("✅ Normalized JSON saved successfully.")

    print_report(input_path, output_path, stats, valid_records)


if __name__ == "__main__":
    main()
