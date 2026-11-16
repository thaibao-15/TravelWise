"""
Module quản lý kết nối và lưu trữ dữ liệu trực tiếp vào SQL Server (TravelWiseDB):
Đảm bảo tự động nhét dữ liệu đầy đủ vào 5 bảng cốt lõi (dòng 75-153 trong TravelWiseDB.sql):
1. places
2. restaurant_details
3. hotel_details
4. place_images
5. opening_hours
"""

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Set
import pyodbc


def get_sqlserver_connection() -> Optional[pyodbc.Connection]:
    """Kết nối tới SQL Server TravelWiseDB qua cấu hình .env."""
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
    try:
        return pyodbc.connect(conn_str)
    except Exception as e:
        print(f"[!] Cảnh báo: Không thể kết nối SQL Server TravelWiseDB: {e}")
        return None


# Ánh xạ chính xác từ key của crawler sang đúng tên trong bảng categories của TravelWiseDB
CATEGORY_MAPPING: Dict[str, str] = {
    "nature": "Thiên nhiên và cảnh quan",
    "culture": "Văn hóa và lịch sử",
    "food": "Ẩm thực",
    "cafe": "Quán cà phê",
    "entertainment": "Vui chơi và giải trí",
    "shopping": "Mua sắm và chợ",
    "hotel": "Lưu trú và nghỉ dưỡng",
    "activity": "Trải nghiệm và hoạt động",
    "wellness": "Thư giãn và chăm sóc sức khỏe",
    "transport": "Giao thông",
    "tour_service": "Dịch vụ du lịch",
    "public_utility": "Tiện ích công cộng",
    "medical": "Y tế",
}


def get_category_id_map(cursor: pyodbc.Cursor) -> Dict[str, int]:
    """Lấy bảng tra cứu category name -> id từ database."""
    cursor.execute("SELECT id, name FROM categories")
    cat_map = {}
    for row in cursor.fetchall():
        cat_map[row.name.strip()] = row.id
    return cat_map


def load_existing_names_and_locations(conn: Optional[pyodbc.Connection]) -> Set[str]:
    """Lấy danh sách các tên địa điểm đã có trong TravelWiseDB để tránh cào lại."""
    existing: Set[str] = set()
    if conn is None:
        return existing
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT LOWER(RTRIM(LTRIM(name))) FROM places WHERE is_deleted = 0")
        for row in cursor.fetchall():
            if row[0]:
                existing.add(row[0])
    except Exception as e:
        print(f"[!] Lỗi khi load tên từ DB: {e}")
    return existing


def insert_place_to_sqlserver(
    conn: Optional[pyodbc.Connection],
    record: Dict[str, Any],
    cat_id_map: Dict[str, int]
) -> bool:
    """
    Import toàn diện 1 bản ghi vào hệ thống 5 bảng của TravelWiseDB:
    - Bảng 1: places
    - Bảng 2: restaurant_details (nếu là food/cafe)
    - Bảng 3: hotel_details (nếu là hotel)
    - Bảng 4: place_images (ảnh đại diện của địa điểm)
    - Bảng 5: opening_hours (giờ mở cửa các thứ trong tuần)
    """
    struct = record.get("structured_data", {})
    name = (struct.get("name") or "").strip()
    if not name:
        return False

    address = (struct.get("address") or "").replace("", "").replace("", "").strip()
    phone = (struct.get("phone") or "").replace("", "").strip()
    website = (struct.get("website") or "").strip()
    lat = struct.get("latitude")
    lng = struct.get("longitude")
    rating = struct.get("rating")
    reviews = struct.get("user_ratings_total")
    description = record.get("description") or f"Địa điểm {name} tại Đà Nẵng"

    crawler_cat = record.get("category", "food")
    db_cat_name = CATEGORY_MAPPING.get(crawler_cat, "Ẩm thực")
    category_id = cat_id_map.get(db_cat_name, 3)

    cuisine_type = struct.get("cuisine_type") or db_cat_name
    price_range = struct.get("price_range") or "Vừa phải"
    star_rating = struct.get("star_rating") or 3

    images: List[str] = record.get("images", [])
    schedules: List[Dict[str, Any]] = record.get("schedules", [])

    for attempt in range(2):
        try:
            if conn is None:
                conn = get_sqlserver_connection()
                if conn is None:
                    return False

            cursor = conn.cursor()

            # 1. Kiểm tra trùng lặp qua STDistance hoặc Name
            if lat is not None and lng is not None:
                check_query = """
                SELECT TOP 1 id FROM places 
                WHERE LOWER(RTRIM(LTRIM(name))) = LOWER(RTRIM(LTRIM(?)))
                   OR (location IS NOT NULL AND location.STDistance(geography::Point(?, ?, 4326)) <= 25)
                """
                cursor.execute(check_query, (name, lat, lng))
            else:
                check_query = "SELECT TOP 1 id FROM places WHERE LOWER(RTRIM(LTRIM(name))) = LOWER(RTRIM(LTRIM(?)))"
                cursor.execute(check_query, (name,))

            if cursor.fetchone():
                return False

            # =================================================================
            # 2. INSERT VÀO BẢNG: places (dòng 84-102)
            # =================================================================
            insert_sql = """
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
                insert_sql,
                (name, description, address, lat, lng, lat, lng, lat, lng, category_id, rating, reviews),
            )
            place_id = cursor.fetchone()[0]

            # =================================================================
            # 3. INSERT VÀO BẢNG: restaurant_details (dòng 110-116)
            # =================================================================
            if crawler_cat in ["food", "cafe"]:
                cursor.execute(
                    """
                    INSERT INTO restaurant_details (place_id, cuisine_type, price_range, is_vegetarian)
                    VALUES (?, ?, ?, ?)
                    """,
                    (place_id, cuisine_type, price_range, 0),
                )

            # =================================================================
            # 4. INSERT VÀO BẢNG: hotel_details (dòng 118-129)
            # =================================================================
            elif crawler_cat == "hotel":
                cursor.execute(
                    """
                    INSERT INTO hotel_details (place_id, star_rating, amenities, phone, website)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (place_id, star_rating, "Wifi, Điều hòa, Thang máy", phone, website),
                )

            # =================================================================
            # 5. INSERT VÀO BẢNG: place_images (dòng 134-141): Lưu tối thiểu 2 ảnh
            # =================================================================
            for idx, img_url in enumerate(images):
                if img_url:
                    is_primary = 1 if idx == 0 else 0
                    desc_img = f"Hình ảnh chính của {name}" if is_primary else f"Hình ảnh không gian/hoạt động của {name}"
                    cursor.execute(
                        """
                        INSERT INTO place_images (place_id, url, description, is_primary)
                        VALUES (?, ?, ?, ?)
                        """,
                        (place_id, img_url, desc_img, is_primary),
                    )

            # =================================================================
            # 6. INSERT VÀO BẢNG: opening_hours (dòng 146-153)
            # =================================================================
            for sch in schedules:
                cursor.execute(
                    """
                    INSERT INTO opening_hours (place_id, day_of_week, open_time, close_time)
                    VALUES (?, ?, ?, ?)
                    """,
                    (place_id, sch["day_of_week"], sch["open_time"], sch["close_time"]),
                )

            conn.commit()
            return True

        except (pyodbc.OperationalError, pyodbc.DatabaseError) as err:
            if attempt == 0:
                conn = get_sqlserver_connection()
                continue
            else:
                print(f"[!] Lỗi khi ghi record {name} vào SQL Server: {err}")
                return False
        except Exception as e:
            print(f"[!] Lỗi: {e}")
            return False

    return False


def save_backup_jsonl(file_path: Path, record: Dict[str, Any]) -> None:
    """Lưu nối tiếp bản ghi backup vào file JSONL."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
        f.flush()


def load_existing_urls_from_jsonl(file_path: Path) -> Set[str]:
    """Đọc URL đã cào từ file JSONL backup."""
    existing_urls: Set[str] = set()
    if not file_path.is_file():
        return existing_urls
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            for line in f:
                line_str = line.strip()
                if not line_str:
                    continue
                try:
                    data = json.loads(line_str)
                    url = data.get("url")
                    if url:
                        existing_urls.add(url.strip())
                except Exception:
                    continue
    except Exception:
        pass
    return existing_urls
