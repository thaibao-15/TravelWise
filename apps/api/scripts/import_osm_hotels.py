"""
Script: import_osm_hotels.py
Description: Unified CLI for TravelWise OpenStreetMap hotel import pipeline.

Modes:
    1. fetch     : Calls Overpass API and saves raw response to data/osm_hotels_raw.json.
    2. normalize : Reads raw JSON, normalizes data, and saves to data/osm_hotels_normalized.json.
    3. dry-run   : Validates and simulates database import without committing any changes.
    4. import    : Executes real database import into SQL Server with idempotency.
    5. pipeline  : Runs the complete end-to-end process (Fetch -> Normalize -> Import/Dry-run)
                   with strict step validation; aborts safely if any step fails.
    6. verify-db : Queries database to verify places, hotel_details links, OSM IDs, and coordinates.

Usage Examples:
    # Mode 1: Fetch raw hotel data from Overpass
    uv run python scripts/import_osm_hotels.py fetch

    # Mode 2: Normalize existing raw hotel data
    uv run python scripts/import_osm_hotels.py normalize

    # Mode 3: Test database import safely (Rollback)
    uv run python scripts/import_osm_hotels.py dry-run --limit 20
    uv run python scripts/import_osm_hotels.py --dry-run

    # Mode 4: Real database import
    uv run python scripts/import_osm_hotels.py import
    uv run python scripts/import_osm_hotels.py import --limit 100

    # Mode 5: Complete pipeline end-to-end (Fetch -> Normalize -> Import)
    uv run python scripts/import_osm_hotels.py pipeline

    # Mode 5 with Dry-run: Complete pipeline end-to-end without DB commit
    uv run python scripts/import_osm_hotels.py pipeline --dry-run

    # Mode 6: Verify imported database records
    uv run python scripts/import_osm_hotels.py verify-db
"""

import argparse
import json
import logging
import os
from pathlib import Path
import sys
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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("osm_hotel_pipeline_cli")

from sqlmodel import Session

from app.db.session import engine
from app.services.osm_hotel_importer_service import OSMHotelImporterService
from app.services.osm_hotel_service import OSMHotelService
from scripts.fetch_osm_hotels import (
    DEFAULT_BBOX,
    fetch_raw_osm_hotels,
    save_atomic_json as save_atomic_raw,
    verify_and_report as verify_raw_report,
)
from scripts.normalize_osm_hotels import (
    print_report as print_normalized_report,
    save_atomic_json as save_atomic_normalized,
)

DEFAULT_RAW_FILE = api_root / "data" / "osm_hotels_raw.json"
DEFAULT_NORMALIZED_FILE = api_root / "data" / "osm_hotels_normalized.json"


# ─── STEP 1: FETCH ────────────────────────────────────────────────────────────

def run_fetch_step(
    output_path: Path,
    bbox: dict[str, float],
    timeout_seconds: int = 60,
    retries: int = 3,
) -> bool:
    """Step 1: Fetch raw hotel elements from Overpass API and save to file."""
    print("\n" + "=" * 56)
    print("📡 [BƯỚC 1/3] THU THẬP DỮ LIỆU TỪ OVERPASS API")
    print(f"📍 Bounding Box  : {bbox}")
    print(f"💾 File lưu raw  : {output_path.resolve()}")
    print("-" * 56)

    try:
        raw_data = fetch_raw_osm_hotels(
            bbox=bbox,
            timeout_seconds=timeout_seconds,
            max_retries=retries,
        )
        print(f"💾 Đang lưu raw JSON vào {output_path.name}...")
        save_atomic_raw(raw_data, output_path)
        print("✅ Lưu file raw thành công.")

        success = verify_raw_report(output_path)
        if not success:
            print("❌ Xác minh file raw thất bại.", file=sys.stderr)
            return False
        return True
    except Exception as exc:
        print(f"❌ [BƯỚC 1 THẤT BẠI] Lỗi khi thu thập từ Overpass: {exc}", file=sys.stderr)
        return False


# ─── STEP 2: NORMALIZE ────────────────────────────────────────────────────────

def run_normalize_step(input_path: Path, output_path: Path) -> tuple[bool, Optional[list[dict[str, Any]]]]:
    """Step 2: Read raw JSON, validate, normalize schema, and save to file."""
    print("\n" + "=" * 56)
    print("⚙️  [BƯỚC 2/3] CHUẨN HÓA DỮ LIỆU KHÁCH SẠN (NORMALIZE)")
    print(f"📥 File đầu vào  : {input_path.resolve()}")
    print(f"📤 File đầu ra   : {output_path.resolve()}")
    print("-" * 56)

    if not input_path.exists():
        print(f"❌ File raw không tồn tại: {input_path}. Vui lòng chạy bước fetch trước.", file=sys.stderr)
        return False, None

    try:
        with open(input_path, "r", encoding="utf-8") as f:
            raw_data = json.load(f)
    except Exception as exc:
        print(f"❌ Không thể đọc file JSON raw {input_path}: {exc}", file=sys.stderr)
        return False, None

    if not isinstance(raw_data, dict) or "elements" not in raw_data:
        print("❌ Dữ liệu không đúng định dạng Overpass (thiếu 'elements').", file=sys.stderr)
        return False, None

    try:
        elements: list[dict[str, Any]] = raw_data.get("elements", [])
        valid_records, discarded, stats = OSMHotelService.normalize_elements(elements)
        print(f"💾 Đang lưu {len(valid_records)} bản ghi chuẩn hóa vào {output_path.name}...")
        save_atomic_normalized(valid_records, output_path)
        print("✅ Lưu file normalized thành công.")

        print_normalized_report(input_path, output_path, stats, valid_records[:5])
        return True, valid_records
    except Exception as exc:
        print(f"❌ [BƯỚC 2 THẤT BẠI] Lỗi trong quá trình chuẩn hóa: {exc}", file=sys.stderr)
        return False, None


# ─── STEP 3: DATABASE IMPORT / DRY-RUN ────────────────────────────────────────

def run_import_step(
    records: list[dict[str, Any]],
    source_description: str,
    limit: Optional[int] = None,
    dry_run: bool = False,
) -> bool:
    """Step 3: Import or Dry-run normalized records into SQL Server with transaction safety."""
    step_label = "DRY-RUN (KIỂM TRA AN TOÀN)" if dry_run else "IMPORT VÀO SQL SERVER"
    print("\n" + "=" * 56)
    print(f"🚀 [BƯỚC 3/3] {step_label}")
    print(f"📁 Nguồn dữ liệu : {source_description}")
    print(f"🛡️  Chế độ        : {'DRY-RUN (Rollback giao dịch, KHÔNG lưu DB)' if dry_run else 'IMPORT THẬT (Commit vào database)'}")
    if limit:
        print(f"🔢 Giới hạn xử lý: {limit} bản ghi")
    print("-" * 56)

    try:
        with Session(engine) as session:
            metrics = OSMHotelImporterService.import_normalized_hotels(
                session=session,
                records=records,
                limit=limit,
                dry_run=dry_run,
            )

        print("\n📊 BÁO CÁO THỐNG KÊ CHI TIẾT TẦNG DATABASE:")
        print(f"   • Danh mục áp dụng        : {metrics['category_name']} (ID={metrics['category_id']})")
        print(f"   • Tổng bản ghi đưa vào xử lý: {metrics['total_records']}")
        print(f"   • Thêm mới (Added)        : {metrics['added_count']}")
        print(f"   • Cập nhật (Updated)      : {metrics['updated_count']}")
        print(f"   • Bỏ qua tại DB (Skipped) : {metrics['skipped_count']}")
        print(f"   • Lỗi phát sinh (Errors)  : {metrics['error_count']}")

        if metrics["errors"]:
            print("\n⚠️  Một số lỗi phát sinh trong batch:")
            for err in metrics["errors"]:
                print(f"     - {err}")

        if dry_run:
            print("\n🔍 KẾT QUẢ: Dry-run thành công, giao dịch đã được ROLLBACK an toàn.")
        else:
            print("\n✅ KẾT QUẢ: Giao dịch đã được COMMIT thành công vào SQL Server.")
        print("=" * 56 + "\n")
        return metrics["error_count"] == 0
    except Exception as exc:
        print(f"❌ [BƯỚC 3 THẤT BẠI] Lỗi kết nối hoặc thực thi database: {exc}", file=sys.stderr)
        return False


def run_verify_db_step() -> bool:
    """Query database to verify hotel counts, details links, OSM identifiers, and sample records."""
    print("\n" + "=" * 56)
    print("🔍 KIỂM TRA DỮ LIỆU KHÁCH SẠN TRONG CƠ SỞ DỮ LIỆU SQL SERVER")
    print("-" * 56)

    try:
        with Session(engine) as session:
            info = OSMHotelImporterService.verify_database_data(session)

        print("📊 BÁO CÁO THỰC TẾ TRONG DATABASE:")
        print(f"   • Danh mục áp dụng          : {info['category_name']} (ID={info['category_id']})")
        print(f"   • Tổng số khách sạn (places): {info['total_places']}")
        print(f"   • Có định danh OSM          : {info['with_osm_ids']}/{info['total_places']}")
        print(f"   • Có tọa độ hợp lệ          : {info['with_coords']}/{info['total_places']}")
        print(f"   • Có liên kết hotel_details : {info['with_details']}/{info['total_places']}")
        print(f"   • Có ảnh trong place_images : {info['with_images']}/{info['total_places']}")

        if info["samples"]:
            print("\n🔍 5 Bản ghi khách sạn mẫu trong Database:")
            for idx, s in enumerate(info["samples"], 1):
                stars_str = f"{s['star_rating']} sao" if s['star_rating'] else "<None>"
                amenities_str = s['amenities'] or "<None>"
                print(f"\n  {idx}. [ID DB: {s['id']}] [{str(s['osm_type']).upper()}:{s['osm_id']}]")
                print(f"     Tên      : {s['name']}")
                print(f"     Tọa độ   : lat={s['latitude']}, lon={s['longitude']}")
                print(f"     Hạng sao : {stars_str}")
                print(f"     Tiện nghi: {amenities_str}")
                if s.get("phone") or s.get("website"):
                    print(f"     Liên hệ  : SĐT={s.get('phone') or '<None>'} | Web={s.get('website') or '<None>'}")
                if s.get("rooms") or s.get("beds"):
                    print(f"     Quy mô   : Phòng={s.get('rooms') or '<None>'} | Giường={s.get('beds') or '<None>'}")
                print(f"     Có ảnh   : {'Có' if s['has_image'] else 'Không'}")
        else:
            print("\n⚠️  Chưa có bản ghi khách sạn nào trong danh mục này.")

        print("=" * 56 + "\n")
        return True

    except Exception as exc:
        print(f"❌ Lỗi khi truy vấn kiểm tra database: {exc}", file=sys.stderr)
        return False


# ─── COMPLETE PIPELINE ORCHESTRATION ──────────────────────────────────────────

def run_pipeline(
    raw_path: Path,
    normalized_path: Path,
    bbox: dict[str, float],
    limit: Optional[int],
    dry_run: bool,
    skip_fetch: bool = False,
) -> bool:
    """Run full end-to-end pipeline with strict step-by-step halting on errors."""
    print("\n" + "=" * 56)
    print("🌟 BẮT ĐẦU QUY TRÌNH TOÀN DIỆN KHÁCH SẠN (END-TO-END PIPELINE)")
    print(f"Chế độ: {'DRY-RUN' if dry_run else 'IMPORT THẬT'}")
    print("=" * 56)

    # 1. Fetch
    if not skip_fetch:
        fetch_ok = run_fetch_step(raw_path, bbox)
        if not fetch_ok:
            print("🛑 Dừng pipeline tại Bước 1 (Thu thập). Giữ nguyên dữ liệu hiện có.", file=sys.stderr)
            return False
    else:
        print(f"\n⏩ Bỏ qua bước Fetch, sử dụng file raw có sẵn: {raw_path}")

    # 2. Normalize
    norm_ok, records = run_normalize_step(raw_path, normalized_path)
    if not norm_ok or records is None:
        print("🛑 Dừng pipeline tại Bước 2 (Chuẩn hóa). Không thay đổi cơ sở dữ liệu.", file=sys.stderr)
        return False

    # 3. Import / Dry-run
    import_ok = run_import_step(
        records=records,
        source_description=f"Pipeline Normalized ({normalized_path})",
        limit=limit,
        dry_run=dry_run,
    )
    if not import_ok:
        print("🛑 Pipeline kết thúc với lỗi ở Bước 3.", file=sys.stderr)
        return False

    print("🎉 TOÀN BỘ QUY TRÌNH KHÁCH SẠN ĐÃ HOÀN TẤT THÀNH CÔNG!")
    return True


# ─── CLI ARGUMENT PARSER ──────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Unified CLI for OpenStreetMap hotel fetching, normalizing, and database import.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", help="Chế độ thực thi")

    # Command: fetch
    p_fetch = subparsers.add_parser("fetch", help="Thu thập dữ liệu thô từ Overpass API và lưu JSON")
    p_fetch.add_argument("--output", "-o", type=str, default=str(DEFAULT_RAW_FILE), help="File lưu raw JSON")
    p_fetch.add_argument("--timeout", "-t", type=int, default=60, help="Thời gian chờ Overpass (giây)")
    p_fetch.add_argument("--retries", "-r", type=int, default=3, help="Số lần thử lại tối đa (default: 3)")
    p_fetch.add_argument("--south", type=float, default=DEFAULT_BBOX["south"])
    p_fetch.add_argument("--west", type=float, default=DEFAULT_BBOX["west"])
    p_fetch.add_argument("--north", type=float, default=DEFAULT_BBOX["north"])
    p_fetch.add_argument("--east", type=float, default=DEFAULT_BBOX["east"])

    # Command: normalize
    p_norm = subparsers.add_parser("normalize", help="Chuẩn hóa dữ liệu từ file raw sang file normalized")
    p_norm.add_argument("--input", "-i", type=str, default=str(DEFAULT_RAW_FILE), help="File raw JSON đầu vào")
    p_norm.add_argument("--output", "-o", type=str, default=str(DEFAULT_NORMALIZED_FILE), help="File normalized đầu ra")

    # Command: dry-run
    p_dry = subparsers.add_parser("dry-run", help="Kiểm tra và giả lập import mà KHÔNG lưu database")
    p_dry.add_argument("--fixture", "-f", "--input", "-i", dest="fixture", type=str, default=str(DEFAULT_NORMALIZED_FILE), help="File JSON nguồn")
    p_dry.add_argument("--limit", "-l", type=int, default=None, help="Giới hạn số bản ghi xử lý")

    # Command: import
    p_imp = subparsers.add_parser("import", help="Thực hiện import thật vào SQL Server")
    p_imp.add_argument("--fixture", "-f", "--input", "-i", dest="fixture", type=str, default=str(DEFAULT_NORMALIZED_FILE), help="File JSON nguồn")
    p_imp.add_argument("--limit", "-l", type=int, default=None, help="Giới hạn số bản ghi xử lý")

    # Command: verify-db
    subparsers.add_parser("verify-db", help="Kiểm tra dữ liệu khách sạn, details, tọa độ và OSM ID trong database")

    # Command: pipeline (End-to-End)
    p_pipe = subparsers.add_parser("pipeline", help="Chạy toàn bộ quy trình tuần tự: Fetch -> Normalize -> Import")
    p_pipe.add_argument("--dry-run", action="store_true", help="Chạy pipeline ở chế độ Dry-run (không lưu DB)")
    p_pipe.add_argument("--skip-fetch", action="store_true", help="Bỏ qua bước gọi Overpass, dùng file raw có sẵn")
    p_pipe.add_argument("--limit", "-l", type=int, default=None, help="Giới hạn số bản ghi nạp vào DB")
    p_pipe.add_argument("--raw-file", type=str, default=str(DEFAULT_RAW_FILE), help="Đường dẫn file raw JSON")
    p_pipe.add_argument("--normalized-file", type=str, default=str(DEFAULT_NORMALIZED_FILE), help="Đường dẫn file normalized JSON")

    # Root flags for backwards compatibility and 1-command runs
    parser.add_argument("--dry-run", action="store_true", help="Chạy ở chế độ dry-run")
    parser.add_argument("--fixture", "-f", type=str, default=None, help="File JSON fixture")
    parser.add_argument("--limit", "-l", type=int, default=None, help="Giới hạn bản ghi")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    command = args.command

    # Backward compatibility: if no subcommand passed, default to dry-run or import
    if command is None:
        if args.dry_run:
            command = "dry-run"
        else:
            command = "import"

    if command == "fetch":
        bbox = {
            "south": args.south,
            "west": args.west,
            "north": args.north,
            "east": args.east,
        }
        ok = run_fetch_step(
            output_path=Path(args.output).resolve(),
            bbox=bbox,
            timeout_seconds=args.timeout,
            retries=args.retries,
        )
        sys.exit(0 if ok else 1)

    elif command == "normalize":
        ok, _ = run_normalize_step(Path(args.input).resolve(), Path(args.output).resolve())
        sys.exit(0 if ok else 1)

    elif command == "dry-run":
        fixture_path = Path(args.fixture if args.fixture else DEFAULT_NORMALIZED_FILE).resolve()
        if not fixture_path.exists():
            print(f"❌ File fixture không tồn tại: {fixture_path}", file=sys.stderr)
            sys.exit(1)
        with open(fixture_path, "r", encoding="utf-8") as f:
            records = json.load(f)
        if isinstance(records, dict) and "elements" in records:
            _, records = run_normalize_step(fixture_path, DEFAULT_NORMALIZED_FILE)
        ok = run_import_step(records, str(fixture_path), limit=args.limit, dry_run=True)
        sys.exit(0 if ok else 1)

    elif command == "import":
        fixture_path = Path(args.fixture if args.fixture else DEFAULT_NORMALIZED_FILE).resolve()
        if not fixture_path.exists():
            print(f"❌ File fixture không tồn tại: {fixture_path}", file=sys.stderr)
            sys.exit(1)
        with open(fixture_path, "r", encoding="utf-8") as f:
            records = json.load(f)
        if isinstance(records, dict) and "elements" in records:
            _, records = run_normalize_step(fixture_path, DEFAULT_NORMALIZED_FILE)
        ok = run_import_step(records, str(fixture_path), limit=args.limit, dry_run=False)
        sys.exit(0 if ok else 1)

    elif command == "verify-db":
        ok = run_verify_db_step()
        sys.exit(0 if ok else 1)

    elif command == "pipeline":
        bbox = DEFAULT_BBOX
        raw_path = Path(args.raw_file).resolve()
        normalized_path = Path(args.normalized_file).resolve()
        ok = run_pipeline(
            raw_path=raw_path,
            normalized_path=normalized_path,
            bbox=bbox,
            limit=args.limit,
            dry_run=args.dry_run,
            skip_fetch=args.skip_fetch,
        )
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
