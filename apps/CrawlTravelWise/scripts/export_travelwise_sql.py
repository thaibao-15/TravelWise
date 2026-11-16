"""
Script sinh file SQL (data_travelwise.sql) chuẩn 100% theo schema TravelWiseDB.sql
- Tự động map category sang category_id của TravelWiseDB
- Tạo đối tượng geography::Point(latitude, longitude, 4326)
- Tự động chèn vào bảng phụ restaurant_details / hotel_details
- Sử dụng điều kiện chống trùng lặp theo Name và Khoảng cách không gian STDistance <= 25m
"""

import json
from pathlib import Path


def generate_travelwise_sql() -> None:
    jsonl_path = Path("data/crawled_places.jsonl")
    sql_path = Path("data_travelwise.sql")

    if not jsonl_path.exists():
        print(f"[X] Không tìm thấy file {jsonl_path}")
        return

    records = []
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line_str = line.strip()
            if line_str:
                records.append(json.loads(line_str))

    # Ánh xạ crawler category sang category_id trong TravelWiseDB:
    # 1: Thiên nhiên và cảnh quan (attraction)
    # 2: Văn hóa và lịch sử
    # 3: Ẩm thực (food)
    # 4: Quán cà phê (cafe)
    # 7: Lưu trú và nghỉ dưỡng (hotel)
    CAT_MAP = {
        "food": 3,
        "cafe": 4,
        "hotel": 7,
        "attraction": 1,
    }

    sql_statements = [
        "-- ============================================================================",
        "-- TRAVELWISEDB DATA IMPORT SCRIPT",
        f"-- Total records: {len(records)}",
        "-- Compatible with TravelWiseDB Schema (SQL Server MSSQL)",
        "-- ============================================================================\n",
        "USE TravelWiseDB;",
        "GO\n",
    ]

    def esc(val):
        if val is None or val == "":
            return "NULL"
        if isinstance(val, (int, float)):
            return str(val)
        clean = str(val).replace("'", "''").replace("", "").replace("", "").strip()
        return f"N'{clean}'"

    for idx, item in enumerate(records, start=1):
        st = item.get("structured_data", {})
        name = esc(st.get("name"))
        desc = esc(item.get("content") or item.get("description"))
        addr = esc(st.get("address"))
        lat = st.get("latitude")
        lng = st.get("longitude")
        rating = st.get("rating") or 0.0
        reviews = st.get("user_ratings_total") or 0
        cat_key = item.get("category", "food")
        category_id = CAT_MAP.get(cat_key, 3)
        phone = esc(st.get("phone"))

        lat_val = f"{lat}" if lat is not None else "NULL"
        lng_val = f"{lng}" if lng is not None else "NULL"
        geo_val = f"geography::Point({lat}, {lng}, 4326)" if (lat is not None and lng is not None) else "NULL"

        # Block kiểm tra chống trùng lặp theo Name hoặc Tọa độ GPS <= 25m
        block = f"""-- [{idx}] {st.get('name')}
IF NOT EXISTS (
    SELECT 1 FROM places 
    WHERE name = {name} 
       OR ({geo_val} IS NOT NULL AND location IS NOT NULL AND location.STDistance({geo_val}) <= 25)
)
BEGIN
    DECLARE @new_place_id_{idx} BIGINT;

    INSERT INTO places (name, description, address, latitude, longitude, location, category_id, rating_avg, review_count, is_deleted, created_at, updated_at)
    VALUES ({name}, {desc}, {addr}, {lat_val}, {lng_val}, {geo_val}, {category_id}, {rating}, {reviews}, 0, GETDATE(), GETDATE());

    SET @new_place_id_{idx} = SCOPE_IDENTITY();
"""
        # Chèn bảng phụ
        if cat_key in ["food", "cafe"]:
            block += f"""
    INSERT INTO restaurant_details (place_id, cuisine_type, price_range, is_vegetarian)
    VALUES (@new_place_id_{idx}, N'Ẩm thực & Đồ uống', N'Vừa phải', 0);
"""
        elif cat_key == "hotel":
            block += f"""
    INSERT INTO hotel_details (place_id, star_rating, amenities, phone)
    VALUES (@new_place_id_{idx}, 3, N'Wifi, Máy lạnh', {phone});
"""
        block += "END;\nGO\n"
        sql_statements.append(block)

    with open(sql_path, "w", encoding="utf-8") as f:
        f.write("\n".join(sql_statements))

    print(f"[v] Đã sinh file {sql_path.resolve()} chứa {len(records)} bản ghi chuẩn TravelWiseDB!")


if __name__ == "__main__":
    generate_travelwise_sql()

