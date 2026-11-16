# Google Maps Crawler -> SQL Server (TravelWiseDB)

Module cào dữ liệu Google Maps tự động và **nạp trực tiếp vào cơ sở dữ liệu SQL Server (TravelWiseDB)**, đồng thời áp dụng thuật toán **chống trùng lặp 2 lớp (Tên + Tọa độ không gian $\le 25$m)**.

---
# 1. Ẩm thực & Nhà hàng (Category ID = 3: Hải sản, đặc sản, nhà hàng fine dining, đồ nướng...)
uv run python main.py --category food --limit 30 --headless

# 8. Lưu trú và nghỉ dưỡng (Category ID = 7: Khách sạn ven biển, resort, homestay, căn hộ du lịch...)
uv run python main.py --category hotel --limit 30 --headless

## 1. Cấu trúc Dự án (Đã tinh gọn 100% cho SQL Server)

```text
gmaps_crawler/
├── data/
│   └── crawled_places.jsonl     # File backup dữ liệu đã cào
├── src/
│   ├── __init__.py
│   ├── config.py                # Danh sách từ khóa theo category & DOM selectors
│   ├── scroller.py              # Cuộn feed Google Maps lấy danh sách URLs
│   ├── extractor.py             # Bóc tách GPS, tên, rating, review, address, phone
│   └── storage.py               # Kết nối pyodbc & Tự động Insert vào SQL Server TravelWiseDB
├── main.py                      # CLI Entrypoint điều khiển cào & tự động nạp DB
├── .env                         # Cấu hình kết nối SQL Server (localhost:1433)
├── pyproject.toml               # Quản lý dependencies (playwright, pyodbc, tqdm)
└── README.md
```

---

## 2. Cách thức Hoạt động & Bảng dữ liệu trong SQL Server

Khi chạy lệnh cào, dữ liệu được ánh xạ và lưu thẳng vào các bảng trong `TravelWiseDB`:

1. **Bảng `places`:**
   - `name`: Tên địa điểm
   - `description`: Mô tả tổng hợp
   - `address`: Địa chỉ chi tiết
   - `latitude`, `longitude`: Tọa độ GPS float
   - `location`: Đối tượng không gian **`geography::Point(lat, lng, 4326)`**
   - `category_id`: Tự động map sang bảng `categories` (Ẩm thực: `3`, Quán cà phê: `4`, Lưu trú: `7`, Thiên nhiên: `1`)
   - `rating_avg`, `review_count`: Điểm sao & số lượt đánh giá
2. **Bảng phụ quan hệ:**
   - Nếu là `food` hoặc `cafe` ➔ Tự động insert vào **`restaurant_details`**.
   - Nếu là `hotel` ➔ Tự động insert vào **`hotel_details`** (lưu số điện thoại, tiện ích).

### Cơ chế chống trùng lặp:
Trước khi insert, hệ thống kiểm tra:
```sql
SELECT TOP 1 id FROM places 
WHERE LOWER(name) = LOWER(@name)
   OR (location IS NOT NULL AND location.STDistance(geography::Point(@lat, @lng, 4326)) <= 25)
```
Nếu đã trùng tên hoặc trùng tọa độ GPS trong bán kính $\le 25$ mét thì **bỏ qua ngay lập tức**.

---

## 3. Danh Sách Lệnh Chạy Cào Dữ Liệu (Chuẩn 13 Categories trong TravelWiseDB)

Chỉ cần chạy lệnh tương ứng từ PowerShell/Terminal, dữ liệu sẽ tự động cào và nạp thẳng vào **5 bảng liên kết trong SQL Server (`TravelWiseDB`)**:

### 🍽️ LỆNH CHUYÊN CÀO NHÀ HÀNG & QUÁN ĂN (ẨM THỰC)
Nếu bạn **chỉ muốn tập trung lấy dữ liệu nhà hàng**, hãy dùng cờ `--category food`:

```powershell
# 1. Cào nhà hàng số lượng vừa phải (mỗi từ khóa lấy 20 nhà hàng)
uv run python main.py --category food --limit 20 --headless

# 2. Cào nhà hàng số lượng lớn (mỗi từ khóa lấy 30-50 nhà hàng, ~200-300 nhà hàng)
uv run python main.py --category food --limit 30 --headless
```
> **Dữ liệu cào về:** Nhà hàng hải sản, view biển, fine dining sang trọng, đồ nướng BBQ, món Nhật/Hàn/Âu, quán chay, đặc sản mì quảng, bánh tráng thịt heo, bún chả cá...  
> **Tự động lưu vào:** Bảng `places` (Category ID = 3 - Ẩm thực), bảng `restaurant_details` (thể loại món & mức giá) và bảng `place_images`.

---

### Danh Sách Lệnh Chi Tiết Theo Từng Nhóm Danh Mục (Chạy Ngầm --headless):

### Nhóm Ẩm Thực, Cafe & Mua Sắm
```powershell
# 1. Ẩm thực & Nhà hàng (Category ID = 3: Hải sản, đặc sản, nhà hàng fine dining, đồ nướng...)
uv run python main.py --category food --limit 30 --headless

# 2. Quán cà phê (Category ID = 4: Cà phê view biển, cafe làm việc, tiệm trà check-in, cafe An Thượng...)
uv run python main.py --category cafe --limit 20 --headless

# 3. Mua sắm và chợ (Category ID = 6: Chợ Hàn, Chợ Cồn, chợ đêm Sơn Trà, siêu thị đặc sản, TTTM...)
uv run python main.py --category shopping --limit 15 --headless
```

### Nhóm Du Lịch, Tham Quan & Khám Phá
```powershell
# 4. Thiên nhiên và cảnh quan (Category ID = 1: Bãi biển, núi, bán đảo, hồ, thác nước...)
uv run python main.py --category nature --limit 15 --headless

# 5. Văn hóa và lịch sử (Category ID = 2: Chùa Linh Ứng, bảo tàng Chăm, di tích Ngũ Hành Sơn...)
uv run python main.py --category culture --limit 15 --headless

# 6. Vui chơi và giải trí (Category ID = 5: Bà Nà Hills, công viên Châu Á, công viên Núi Thần Tài, phố đi bộ...)
uv run python main.py --category entertainment --limit 10 --headless

# 7. Trải nghiệm và hoạt động (Category ID = 8: Chèo sup, kayak, tour lặn san hô, cắm trại, dù lượn...)
uv run python main.py --category activity --limit 10 --headless
```

### Nhóm Lưu Trú, Nghỉ Dưỡng & Sức Khỏe
```powershell
# 8. Lưu trú và nghỉ dưỡng (Category ID = 7: Khách sạn ven biển, resort, homestay, căn hộ du lịch...)
uv run python main.py --category hotel --limit 30 --headless

# 9. Thư giãn và chăm sóc sức khỏe (Category ID = 9: Spa massage thư giãn, xông hơi thảo dược, foot massage...)
uv run python main.py --category wellness --limit 10 --headless
```

### Nhóm Dịch Vụ, Giao Thông & Tiện Ích
```powershell
# 10. Giao thông (Category ID = 10: Sân bay quốc tế Đà Nẵng, ga tàu, bến xe, bến du thuyền...)
uv run python main.py --category transport --limit 5 --headless

# 11. Dịch vụ du lịch (Category ID = 11: Cho thuê xe máy, xe tự lái, điểm đặt tour du lịch...)
uv run python main.py --category tour_service --limit 5 --headless

# 12. Tiện ích công cộng (Category ID = 12: Bãi đỗ xe công cộng, cây ATM trung tâm...)
uv run python main.py --category public_utility --limit 5 --headless

# 13. Y tế (Category ID = 13: Bệnh viện Vinmec, bệnh viện Đà Nẵng, phòng khám, nhà thuốc lớn...)
uv run python main.py --category medical --limit 5 --headless
```

---

### Lệnh Chạy Tự Động Toàn Diện (Tất Cả 13 Danh Mục)
Nếu muốn crawler tự động quét **TẤT CẢ 13 danh mục** cùng lúc và chạy ngầm dưới nền:
```powershell
uv run python main.py --category all --limit 15 --headless
```

---

## 4. Đồng Bộ Lại Dữ Liệu Khi Lỡ Reset / Xóa Database
Nếu bạn vừa reset hoặc xóa database mà trong file `data/crawled_places.jsonl` đã có sẵn dữ liệu cào từ trước, bạn **không cần phải tốn thời gian cào lại từ đầu**. Chỉ cần chạy 1 lệnh để nạp bù toàn bộ vào SQL Server:

```powershell
uv run python scripts/import_backup.py
```
> Script sẽ tự động đọc file backup, lọc bỏ các địa điểm trùng lặp và đẩy toàn bộ dữ liệu vào đúng 5 bảng trong `TravelWiseDB`.
