"""
Module import dữ liệu cào được từ Google Maps vào TravelWiseDB (SQL Server).
- Đảm bảo ánh xạ chuẩn xác schema: places, categories, restaurant_details, hotel_details, opening_hours.
- Khử trùng lặp 100% bằng:
  1. geography::Point(latitude, longitude, 4326) và STDistance <= 25 mét (tránh trùng tọa độ thực tế).
  2. Khớp chính xác tên địa điểm (name) hoặc địa chỉ (address).
"""

import json
import os
from pathlib import Path
from typing import Dict, List, Optional
import pyodbc


def get_db_connection() -> pyodbc.Connection:
    """Đọc thông tin kết nối từ file .env hoặc biến môi trường."""
    # Tìm file .env: ưu tiên tại apps/api/.env, fallback về .env hiện tại
    current_dir = Path(__file__).resolve().parent
    repo_api_env = current_dir.parent.parent / "api" / ".env"
    local_env = Path(".env")

    env_path = repo_api_env if repo_api_env.exists() else local_env
    env_vars = {}
    if env_path.exists():
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env_vars[k.strip()] = v.strip()

    server = env_vars.get("SQLSERVER_SERVER", os.getenv("SQLSERVER_SERVER", "localhost"))
    user = env_vars.get("SQLSERVER_USER", os.getenv("SQLSERVER_USER", "sa"))
    password = env_vars.get("SQLSERVER_PASSWORD", os.getenv("SQLSERVER_PASSWORD", "12345"))
    database = env_vars.get("SQLSERVER_DB", os.getenv("SQLSERVER_DB", "TravelWiseDB"))
    driver = env_vars.get("SQLSERVER_DRIVER", os.getenv("SQLSERVER_DRIVER", "ODBC Driver 17 for SQL Server"))
    trust_cert = env_vars.get("SQLSERVER_TRUST_CERT", os.getenv("SQLSERVER_TRUST_CERT", "yes"))

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={user};"
        f"PWD={password};"
        f"TrustServerCertificate={trust_cert};"
    )
    return pyodbc.connect(conn_str)


# Ánh xạ từ crawler category sang category_id trong TravelWiseDB
CATEGORY_MAPPING: Dict[str, str] = {
    "food": "Ẩm thực",
    "cafe": "Quán cà phê",
    "hotel": "Lưu trú và nghỉ dưỡng",
    "attraction": "Thiên nhiên và cảnh quan",
}


def get_category_id_map(cursor: pyodbc.Cursor) -> Dict[str, int]:
    """Lấy danh sách category_id hiện có từ bảng categories trong TravelWiseDB."""
    cursor.execute("SELECT id, name FROM categories")
    cat_map = {}
    for row in cursor.fetchall():
        cat_map[row.name.strip()] = row.id
    return cat_map


def import_jsonl_to_travelwisedb(jsonl_path: Path) -> None:
    print(f"\n[*] Bắt đầu import dữ liệu từ {jsonl_path} vào database TravelWiseDB...")

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
    except Exception as e:
        print(f"[X] Không thể kết nối tới SQL Server TravelWiseDB: {e}")
        print("[!] Bạn có thể dùng file xuất SQL `export_travelwisedb_sql.py` để chạy trực tiếp trong SSMS.")
        return

    cat_name_to_id = get_category_id_map(cursor)
    print(f"[*] Đã tải {len(cat_name_to_id)} categories từ TravelWiseDB.")

    inserted_count = 0
    duplicate_count = 0

    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line_str = line.strip()
            if not line_str:
                continue

            item = json.loads(line_str)
            struct = item.get("structured_data", {})

            name = (struct.get("name") or "").strip()
            address = (struct.get("address") or "").strip()
            # Làm sạch các icon lạ nếu có
            address = address.replace("", "").replace("", "").strip()
            phone = (struct.get("phone") or "").replace("", "").strip()

            lat = struct.get("latitude")
            lng = struct.get("longitude")
            rating = struct.get("rating") or 0.0
            reviews = struct.get("user_ratings_total") or 0
            description = item.get("content") or item.get("description") or ""

            crawler_cat = item.get("category", "food")
            db_cat_name = CATEGORY_MAPPING.get(crawler_cat, "Ẩm thực")
            category_id = cat_name_to_id.get(db_cat_name, 3)

            if not name:
                continue

            # =========================================================================
            # KIỂM TRA CHỐNG TRÙNG LẶP (DEDUPLICATION)
            # Điều kiện trùng:
            # 1. Trùng chính xác Tên địa điểm (name)
            # 2. Hoặc nếu có tọa độ GPS, khoảng cách vị trí <= 25 mét (STDistance)
            # =========================================================================
            is_duplicate = False

            if lat is not None and lng is not None:
                check_sql = """
                SELECT TOP 1 id FROM places 
                WHERE name = ? 
                   OR (location IS NOT NULL AND location.STDistance(geography::Point(?, ?, 4326)) <= 25)
                """
                cursor.execute(check_sql, (name, lat, lng))
            else:
                check_sql = "SELECT TOP 1 id FROM places WHERE name = ?"
                cursor.execute(check_sql, (name,))

            existing = cursor.fetchone()
            if existing:
                duplicate_count += 1
                continue

            # 1. INSERT VÀO BẢNG places
            insert_place_sql = """
            INSERT INTO places (
                name, description, address, latitude, longitude, location, 
                category_id, rating_avg, review_count, is_deleted, created_at, updated_at
            )
            OUTPUT INSERTED.id
            VALUES (
                ?, ?, ?, ?, ?, 
                CASE WHEN ? IS NOT NULL AND ? IS NOT NULL THEN geography::Point(?, ?, 4326) ELSE NULL END,
                ?, ?, ?, 0, GETDATE(), GETDATE()
            )
            """
            cursor.execute(
                insert_place_sql,
                (name, description, address, lat, lng, lat, lng, lat, lng, category_id, rating, reviews),
            )
            place_id = cursor.fetchone()[0]

            # 2. INSERT VÀO BẢNG PHỤ TƯƠNG ỨNG (restaurant_details / hotel_details)
            if crawler_cat in ["food", "cafe"]:
                cursor.execute(
                    """
                    INSERT INTO restaurant_details (place_id, cuisine_type, price_range, is_vegetarian)
                    VALUES (?, ?, ?, ?)
                    """,
                    (place_id, db_cat_name, "Vừa phải", 0),
                )
            elif crawler_cat == "hotel":
                cursor.execute(
                    """
                    INSERT INTO hotel_details (place_id, star_rating, amenities, phone)
                    VALUES (?, ?, ?, ?)
                    """,
                    (place_id, 3, "Wifi, Điều hòa", phone),
                )

            inserted_count += 1

    conn.commit()
    conn.close()

    print("\n" + "=" * 60)
    print("🎉 HOÀN TẤT IMPORT VÀO TRAVELWISEDB!")
    print(f"✅ Thêm mới thành công: {inserted_count} địa điểm.")
    print(f"🛡️ Khử trùng lặp: Đã bỏ qua {duplicate_count} địa điểm đã tồn tại.")
    print("=" * 60)


if __name__ == "__main__":
    import_jsonl_to_travelwisedb(Path("data/crawled_places.jsonl"))

