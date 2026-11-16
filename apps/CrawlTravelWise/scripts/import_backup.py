"""
Script độc lập đọc file data/crawled_places.jsonl và tự động import bù toàn bộ vào SQL Server TravelWiseDB.
- Khử trùng lặp 2 lớp: Bỏ qua quán trùng tên hoặc trùng tọa độ GPS (STDistance <= 25m) đã có trong DB.
- Nạp đầy đủ 5 bảng: places, restaurant_details, hotel_details, place_images, opening_hours.
"""

from pathlib import Path
import json
import sys
from src.storage import (
    get_sqlserver_connection,
    get_category_id_map,
    insert_place_to_sqlserver,
)


def import_backup_to_db(jsonl_file: Path = Path("data/crawled_places.jsonl")) -> None:
    if not jsonl_file.is_file():
        print(f"[X] Không tìm thấy file {jsonl_file}")
        sys.exit(1)

    print("=" * 65)
    print("🚀 BẮT ĐẦU IMPORT DỮ LIỆU TỪ JSONL VÀO SQL SERVER TRAVELWISEDB")
    print(f"📁 Nguồn file: {jsonl_file.resolve()}")
    print("=" * 65)

    conn = get_sqlserver_connection()
    if conn is None:
        print("[X] Không thể kết nối tới SQL Server. Vui lòng kiểm tra lại SQL Server Service!")
        sys.exit(1)

    cursor = conn.cursor()
    cat_id_map = get_category_id_map(cursor)
    print(f"[+] Kết nối DB thành công! Đã tải {len(cat_id_map)} categories.")

    records = []
    with open(jsonl_file, "r", encoding="utf-8") as f:
        for line in f:
            line_str = line.strip()
            if line_str:
                records.append(json.loads(line_str))

    print(f"[*] Tìm thấy {len(records)} địa điểm trong file backup.")

    inserted_count = 0
    duplicate_count = 0

    for idx, record in enumerate(records, start=1):
        name = record.get("structured_data", {}).get("name", "N/A")
        print(f"[{idx}/{len(records)}] Đang kiểm tra & import: {name[:30]}...", end="\r")

        success = insert_place_to_sqlserver(conn, record, cat_id_map)
        if success:
            inserted_count += 1
        else:
            duplicate_count += 1

    conn.close()

    print("\n" + "=" * 65)
    print("🎉 HOÀN TẤT ĐỒNG BỘ DỮ LIỆU VÀO TRAVELWISEDB!")
    print(f"✅ Thêm mới thành công vào DB: {inserted_count} địa điểm.")
    print(f"🛡️ Khử trùng lặp: Đã bỏ qua {duplicate_count} địa điểm đã có sẵn trong DB.")
    print("=" * 65)


if __name__ == "__main__":
    import_backup_to_db()

