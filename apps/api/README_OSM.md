# 🗺️ OpenStreetMap Restaurant Fetching & Normalization Module

Tài liệu này mô tả chi tiết module thu thập và chuẩn hóa dữ liệu nhà hàng từ **OpenStreetMap (OSM)** thông qua **Overpass API** trong backend TravelWise (`apps/api`).

Module được thiết kế để chuẩn bị nguồn dữ liệu phong phú về ẩm thực và nhà hàng tại Đà Nẵng, phục vụ trực tiếp cho cơ sở dữ liệu địa điểm du lịch (`places`), chi tiết nhà hàng (`restaurant_details`), giờ mở cửa (`opening_hours`), và công cụ lập lịch trình AI (Trip Planner).

---

## 📌 Mục lục

1. [Tổng quan Kiến trúc](#1-tổng-quan-kiến-trúc)
2. [Cấu trúc Thư mục & File](#2-cấu-trúc-thư-mục--file)
3. [Quy tắc Chuẩn hóa Dữ liệu](#3-quy-tắc-chuẩn-hóa-dữ-liệu)
4. [Cấu hình Hệ thống](#4-cấu-hình-hệ-thống)
5. [Hướng dẫn Sử dụng Code (API Usage)](#5-hướng-dẫn-sử-dụng-code-api-usage)
6. [Cơ chế Chống lỗi Mạng & Rate Limit](#6-cơ-chế-chống-lỗi-mạng--rate-limit)
7. [Hướng dẫn Chạy Kiểm thử (Unit Tests)](#7-hướng-dẫn-chạy-kiểm-thử-unit-tests)
8. [Lộ trình Triển khai Tiếp theo](#8-lộ-trình-triển-khai-tiếp-theo)

---

## 1. Tổng quan Kiến trúc

Luồng dữ liệu hoạt động hoàn toàn bất đồng bộ (`async def`) sử dụng `httpx.AsyncClient`:

```text
Overpass API (https://overpass-api.de/api/interpreter)
                 |
                 | HTTP POST (Overpass QL [out:json])
                 v
   OSMRestaurantService.fetch_raw_elements()
      - Timeout & Network error handling
      - Retry với exponential backoff (HTTP 429, 5xx)
                 |
                 v
     Danh sách raw elements (node, way, relation)
                 |
                 v
   OSMRestaurantService.normalize_elements()
      - Trích xuất tọa độ (lat/lon trực tiếp hoặc center)
      - Ghép địa chỉ có cấu trúc từ addr:*
      - Chuẩn hóa loại hình ẩm thực (cuisine)
      - Phân tích giờ mở cửa (defensive parser)
      - Ánh xạ cờ ăn chay & hình ảnh / Wikimedia Commons
                 |
                 v
     List[NormalizedRestaurant]
                 |
       (Sẵn sàng cho tầng lưu Database)
```

---

## 2. Cấu trúc Thư mục & File

Các file thuộc module này bao gồm:

| File | Thành phần | Trách nhiệm |
|---|---|---|
| [`app/core/config.py`](app/core/config.py) | **Configuration** | Quản lý biến môi trường Overpass URL, timeout, số lần retry và tọa độ Bounding Box Đà Nẵng. |
| [`app/schemas/osm_restaurant.py`](app/schemas/osm_restaurant.py) | **Schemas (Pydantic)** | Định nghĩa `OSMBoundingBox`, `OpeningHourSlot` và `NormalizedRestaurant`. |
| [`app/services/osm_restaurant_service.py`](app/services/osm_restaurant_service.py) | **Service** | Xây dựng câu truy vấn Overpass QL, gửi HTTP POST, retry, và chuẩn hóa từng element OSM. |
| [`scripts/fetch_osm_restaurants.py`](scripts/fetch_osm_restaurants.py) | **CLI Script (Bước 1)** | Tải dữ liệu JSON thô từ Overpass API và lưu nguyên tử vào `data/osm_restaurants_raw.json`. |
| `data/osm_restaurants_raw.json` | **Raw Data** | Dữ liệu JSON gốc tải về từ Overpass API (881 elements tại Đà Nẵng). |
| [`scripts/normalize_osm_restaurants.py`](scripts/normalize_osm_restaurants.py) | **CLI Script (Bước 2)** | Đọc JSON thô, lọc bỏ bản ghi thiếu tên/tọa độ, và chuẩn hóa cấu trúc vào `data/osm_restaurants_normalized.json`. |
| `data/osm_restaurants_normalized.json` | **Normalized Data** | 809 bản ghi nhà hàng hợp lệ đã chuẩn hóa cấu trúc sẵn sàng lưu database. |
| [`tests/test_osm_restaurant.py`](tests/test_osm_restaurant.py) | **Unit Tests** | 13 test cases cho Service và Overpass HTTP mock. |
| [`tests/test_normalize_script.py`](tests/test_normalize_script.py) | **Unit Tests** | 8 test cases kiểm thử logic lọc và chuẩn hóa của script. |

---

## 3. Quy tắc Chuẩn hóa Dữ liệu

Module tuân thủ nguyên tắc **"Không tự phỏng đoán dữ liệu" (No ungrounded heuristics)**:

### 3.1. Tọa độ (Coordinates)
* **Node:** Đọc trực tiếp trường `lat` và `lon` ở gốc phần tử.
* **Way & Relation:** Truy vấn Overpass với `out body center;` để Overpass tính trước điểm trọng tâm. Tọa độ được đọc từ trường `center.lat` và `center.lon`.
* **Dữ liệu thiếu:** Nếu không có hoặc giá trị không phải số hợp lệ trong dải [-90, 90] và [-180, 180], giá trị được gán là `None`.

### 3.2. Tên Nhà hàng
* Ưu tiên các tag: `name` ➔ `name:vi` ➔ `name:en` ➔ `int_name`.
* Cắt tỉa khoảng trắng thừa (`strip()`). Nếu không có tag nào, gán `None`.

### 3.3. Địa chỉ
* Ưu tiên tag `addr:full` nếu đã có sẵn địa chỉ hoàn chỉnh.
* Nếu thiếu `addr:full`, kết hợp các trường hiện có theo thứ tự:
  $$\text{Số nhà} + \text{Tên đường} \rightarrow \text{Phường/Khu phố} \rightarrow \text{Quận/Huyện} \rightarrow \text{Thành phố}$$
* Hỗ trợ đọc cả tag dạng `contact:street`, `contact:city`, v.v. Nếu tất cả đều rỗng, địa chỉ là `None`.

### 3.4. Giờ mở cửa (`opening_hours`)
* Luôn lưu chuỗi gốc vào `opening_hours_raw`.
* Bộ phân tích [`parse_opening_hours`](app/services/osm_restaurant_service.py) hỗ trợ:
  * `24/7` ➔ Tạo 7 slot từ `00:00` đến `23:59` cho cả tuần (thứ 2 đến Chủ nhật: `0` .. `6`).
  * `Mo-Su 08:00-22:00`, `Mo-Fr 07:00-21:00; Sa-Su 08:00-22:00`.
  * Các chuỗi thời gian phân cách bởi dấu phẩy hoặc chấm phẩy.
* Các chuỗi phức tạp không parse được sẽ trả về danh sách rỗng (`[]`) mà không làm gián đoạn chương trình.

### 3.5. Chế độ ăn chay (`is_vegetarian`)
* Trả về `True` nếu `diet:vegetarian` hoặc `vegetarian` là `"yes"` hoặc `"only"`.
* Trả về `False` nếu tag là `"no"`.
* Mọi trường hợp khác giữ `None`, tuyệt đối không đoán dựa theo tên nhà hàng.

### 3.6. Hình ảnh & Wikimedia Commons
* Nếu tag `image` bắt đầu bằng `http://` hoặc `https://`: Gán vào `image_url`.
* Nếu có tag `wikimedia_commons` hoặc `image` dạng `File:...`: Tự động chuyển đổi thành URL ảnh trực tiếp từ Wikimedia Commons:
  `https://commons.wikimedia.org/wiki/Special:FilePath/{encoded_file_name}`.

---

## 4. Cấu hình Hệ thống

Các thông số cấu hình tại [`app/core/config.py`](app/core/config.py) có thể tùy biến qua file `.env`:

```env
# URL Overpass API (Mặc định: server chính thức của OpenStreetMap)
OVERPASS_API_URL=https://overpass-api.de/api/interpreter

# Thời gian chờ (giây) cho mỗi request Overpass
OVERPASS_TIMEOUT_SECONDS=30.0

# Số lần thử lại tối đa khi gặp lỗi HTTP 429 hoặc lỗi 5xx
OVERPASS_MAX_RETRIES=3

# Thời gian chờ ban đầu giữa các lần retry (giây, áp dụng backoff x2)
OVERPASS_RETRY_BACKOFF_SECONDS=2.0

# Bounding box khu vực Đà Nẵng
DANANG_BBOX_SOUTH=15.90
DANANG_BBOX_WEST=107.90
DANANG_BBOX_NORTH=16.25
DANANG_BBOX_EAST=108.35
```

---

## 5. Hướng dẫn Sử dụng Code (API Usage)

### 5.1. Thu thập & Chuẩn hóa toàn bộ nhà hàng tại Đà Nẵng

```python
import asyncio
from app.services.osm_restaurant_service import OSMRestaurantService

async def main():
    # Sử dụng bounding box mặc định cấu hình cho Đà Nẵng
    restaurants = await OSMRestaurantService.get_normalized_restaurants(
        skip_unnamed=True,        # Bỏ qua địa điểm không có tên
        skip_missing_coords=True  # Bỏ qua địa điểm không có tọa độ
    )
    
    print(f"Lấy được {len(restaurants)} nhà hàng hợp lệ.")
    for r in restaurants[:5]:
        print(f"- [{r.osm_type}/{r.osm_id}] {r.name} | Tọa độ: ({r.latitude}, {r.longitude}) | Cuisine: {r.cuisine}")

if __name__ == "__main__":
    asyncio.run(main())
```

### 5.2. Chỉ định Bounding Box tùy chỉnh

```python
from app.schemas.osm_restaurant import OSMBoundingBox
from app.services.osm_restaurant_service import OSMRestaurantService

# Quét khu vực quận Hải Châu, Đà Nẵng
custom_bbox = OSMBoundingBox(
    south=16.03,
    west=108.20,
    north=16.08,
    east=108.24
)

restaurants = await OSMRestaurantService.get_normalized_restaurants(bbox=custom_bbox)
```

### 5.3. Chuẩn hóa dữ liệu từ file JSON tải sẵn

Nếu bạn đã có file JSON tải từ Overpass Turbo hoặc lưu từ trước:

```python
import json
from app.services.osm_restaurant_service import OSMRestaurantService

with open("raw_osm_data.json", "r", encoding="utf-8") as f:
    data = json.load(f)

# Chuẩn hóa danh sách phần tử
normalized_list = OSMRestaurantService.normalize_elements(data["elements"])
```

---

## 6. Cơ chế Chống lỗi Mạng & Rate Limit

Overpass API là dịch vụ công cộng có giới hạn tải nghiêm ngặt. Module triển khai các lớp bảo vệ:

1. **HTTP POST thay vì GET:** Câu lệnh truy vấn được gửi trong phần thân HTTP POST (`data={"data": query}`) giúp tránh giới hạn độ dài URL và giảm tải caching thừa.
2. **Xử lý HTTP 429 (Too Many Requests):** Tự động phát hiện khi Overpass bị quá tải, tạm dừng theo cấp số nhân (`exponential backoff`) trước khi thử lại.
3. **Xử lý Timeout & 5xx:** Xử lý `httpx.TimeoutException`, HTTP 500, 502, 503, 504 và retry tối đa số lần cho phép (`OVERPASS_MAX_RETRIES`).
4. **Không retry đối với lỗi 400 (Bad Request):** Nếu câu truy vấn sai cú pháp, hệ thống dừng ngay lập tức để tránh lãng phí tài nguyên.

---

## 7. Hướng dẫn Chạy Kiểm thử (Unit Tests)

Bộ kiểm thử được viết bằng `unittest` chuẩn của Python, sử dụng `unittest.mock` để giả lập toàn bộ phản hồi HTTP và dữ liệu OSM.

### Lệnh thực thi:

Mở terminal tại thư mục `apps/api`:

```powershell
uv run python -m unittest tests/test_osm_restaurant.py -v
```

### Danh sách các test cases:

* `test_build_overpass_query`: Sinh câu lệnh Overpass QL đúng chuẩn.
* `test_bounding_box_validation`: Bắt lỗi khi nhập tọa độ BBox không hợp lệ.
* `test_normalize_node_element`: Chuẩn hóa phần tử kiểu `node`.
* `test_normalize_way_element_with_center`: Chuẩn hóa phần tử kiểu `way` có tọa độ `center`.
* `test_normalize_relation_element_with_split_opening_hours`: Chuẩn hóa `relation` và tách nhiều khung giờ mở cửa.
* `test_normalize_way_missing_center`: Xử lý an toàn khi thiếu tọa độ `center`.
* `test_normalize_missing_sparse_data_strict_nulls`: Đảm bảo trường thiếu nhận `None` mà không phỏng đoán.
* `test_opening_hours_24_7`: Chuẩn hóa định dạng `24/7`.
* `test_opening_hours_unparseable_fails_gracefully`: Không văng lỗi khi gặp chuỗi giờ mở cửa phức tạp.
* `test_filter_unnamed_and_missing_coords`: Lọc bỏ địa điểm thiếu dữ liệu bắt buộc.
* `test_fetch_raw_elements_success`: Giả lập HTTP POST thành công.
* `test_fetch_raw_elements_retries_on_429`: Giả lập phản hồi 429 và cơ chế retry.
* `test_fetch_raw_elements_invalid_json`: Giả lập phản hồi JSON lỗi và ném `HTTP 502`.

---

---

## 8. Hướng dẫn CLI Quản lý & Import Toàn Diện

Kịch bản CLI [`scripts/import_osm_restaurants.py`](scripts/import_osm_restaurants.py) là công cụ điều khiển thống nhất cho toàn bộ quy trình:

### 8.1. Chế độ Từng Bước (Individual Modes)

1. **Chế độ Fetch (Thu thập JSON gốc từ Overpass API):**
   ```powershell
   uv run python scripts/import_osm_restaurants.py fetch
   # Hoặc tùy biến bounding box và output:
   uv run python scripts/import_osm_restaurants.py fetch --output data/osm_restaurants_raw.json --timeout 60
   ```

2. **Chế độ Normalize (Chuẩn hóa schema từ file raw):**
   ```powershell
   uv run python scripts/import_osm_restaurants.py normalize
   # Hoặc chỉ định file:
   uv run python scripts/import_osm_restaurants.py normalize -i data/osm_restaurants_raw.json -o data/osm_restaurants_normalized.json
   ```

3. **Chế độ Dry-Run (Kiểm tra an toàn tầng database, Rollback hoàn toàn):**
   ```powershell
   uv run python scripts/import_osm_restaurants.py dry-run --limit 20
   # Dùng file fixture tùy ý:
   uv run python scripts/import_osm_restaurants.py dry-run --fixture data/osm_restaurants_normalized.json
   ```

4. **Chế độ Import (Ghi và cập nhật vào SQL Server):**
   ```powershell
   uv run python scripts/import_osm_restaurants.py import
   # Hoặc giới hạn số lượng:
   uv run python scripts/import_osm_restaurants.py import --limit 100
   ```

---

### 8.2. Chế độ Toàn Bộ Quy Trình (Pipeline Mode - 1 Lệnh Duy Nhất)

Quy trình chạy tuần tự 3 bước: **Fetch ➔ Normalize ➔ Database (Dry-run hoặc Import thật)**.
*Nếu một bước thất bại, toàn bộ quy trình sẽ dừng ngay lập tức để bảo vệ dữ liệu hợp lệ.*

* **Chạy Pipeline ở chế độ Dry-Run (An toàn tuyệt đối):**
  ```powershell
  uv run python scripts/import_osm_restaurants.py pipeline --dry-run
  ```

* **Chạy Pipeline bỏ qua bước gọi Overpass (Dùng file raw sẵn có):**
  ```powershell
  uv run python scripts/import_osm_restaurants.py pipeline --skip-fetch --dry-run --limit 20
  ```

* **Chạy Pipeline Import Thật:**
  ```powershell
  uv run python scripts/import_osm_restaurants.py pipeline
  ```
