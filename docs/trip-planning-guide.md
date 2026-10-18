# Hướng dẫn Trip Planner của TravelWise

Tài liệu này mô tả tính năng tạo và quản lý chuyến đi (Trip Planner), từ lúc
người dùng trò chuyện với AI đến lúc lịch trình được sinh, kiểm tra và lưu vào
SQL Server.

## 1. Tổng quan

Trip Planner gồm các phần chính:

```text
Tin nhắn người dùng
        |
        v
TripPlanningContextExtractionService
        |
        v
TripPlanningContext
        |
        +--> PlaceSearchService tìm địa điểm thực tế
        |
        v
ItineraryGenerationService gọi LLM
        |
        v
Validate / sanitize lịch trình
        |
        v
ItineraryPersistenceService lưu Trip, Days và Activities
```

LLM không được tự tạo địa điểm hoặc `place_id`. LLM chỉ được chọn địa điểm từ
danh sách ứng viên do `PlaceSearchService` lấy từ database.

## 2. Các thành phần quan trọng

| Thành phần | Vị trí | Trách nhiệm |
|---|---|---|
| API route | [`apps/api/app/api/routes/trips.py`](../apps/api/app/api/routes/trips.py) | Nhận request, kiểm tra quyền và gọi service |
| Planning context | [`apps/api/app/schemas/trip_planning.py`](../apps/api/app/schemas/trip_planning.py) | Chuẩn hóa điểm đến, ngày, ngân sách, sở thích, GPS |
| Itinerary request/response | [`apps/api/app/schemas/itinerary.py`](../apps/api/app/schemas/itinerary.py) | Contract của API tạo lịch trình |
| Place search | [`apps/api/app/services/place_search_service.py`](../apps/api/app/services/place_search_service.py) | Lọc, xếp hạng và tìm địa điểm thực tế |
| LLM itinerary service | [`apps/api/app/services/itinerary_generation_service.py`](../apps/api/app/services/itinerary_generation_service.py) | Tạo prompt, gọi LLM, kiểm tra và làm sạch JSON |
| Persistence | [`apps/api/app/services/itinerary_persistence_service.py`](../apps/api/app/services/itinerary_persistence_service.py) | Lưu cấu trúc lịch trình vào SQL Server |
| Web API client | [`apps/web/services/chat.service.ts`](../apps/web/services/chat.service.ts) | Gọi API từ frontend |
| Chat orchestration | [`apps/web/hooks/useChat.ts`](../apps/web/hooks/useChat.ts) | Tạo lịch trình từ đề xuất trong chat |
| Trip creation page | [`apps/web/app/trips/new/page.tsx`](../apps/web/app/trips/new/page.tsx) | Tạo trip và sinh itinerary đầu tiên |

## 3. Hai cách tạo lịch trình

### 3.1. Tạo trực tiếp từ context hoặc conversation

```http
POST /api/v1/trips/generate
Content-Type: application/json
```

Dùng khi chưa có `trip_id`. Backend có thể tự tạo Trip nếu
`save_to_db=true`.

### 3.2. Tạo cho một Trip đã tồn tại

```http
POST /api/v1/trips/{trip_id}/itinerary/generate
Content-Type: application/json
Authorization: Bearer <access-token>
```

Dùng khi frontend đã tạo Trip trước. Nếu không truyền `context`, backend lần
lượt thử lấy context từ:

1. `TripPreference.raw_context_snapshot`.
2. Conversation liên kết với Trip.
3. Các trường cơ bản của Trip như thành phố và ngày bắt đầu/kết thúc.

## 4. Request mẫu

```json
{
  "context": {
    "trip": {
      "destination": {
        "city": "Đà Nẵng",
        "country": "Việt Nam",
        "additional_destinations": []
      },
      "dates": {
        "duration_days": 3,
        "start_date": "2026-11-01",
        "end_date": "2026-11-03"
      },
      "travelers": {
        "adults": 2,
        "children": 0,
        "group_type": "COUPLE"
      }
    },
    "budget": {
      "total": 5000000,
      "currency": "VND"
    },
    "preferences": {
      "travel_style": ["thư giãn"],
      "interests": ["biển", "ẩm thực"]
    },
    "place_requirements": {
      "must_visit": ["Bãi biển Mỹ Khê"],
      "preferred": [],
      "excluded": []
    },
    "schedule_constraints": {
      "pace": "MODERATE",
      "group_nearby_places": true
    }
  },
  "current_location": {
    "latitude": 16.0544,
    "longitude": 108.2022
  },
  "save_to_db": true,
  "user_prompt": "Ưu tiên các địa điểm gần nhau trong cùng một ngày."
}
```

Các trường chính:

- `context`: thông tin kế hoạch đã chuẩn hóa.
- `current_location`: GPS hiện tại, không bắt buộc.
- `save_to_db`: có lưu lịch trình vào database hay chỉ trả kết quả.
- `user_prompt`: yêu cầu điều chỉnh mới nhất của người dùng.
- `conversation_id`: dùng với endpoint `/trips/generate` nếu lấy context từ hội thoại.

## 5. Quy tắc xử lý vị trí hiện tại

`current_location` là vị trí thiết bị tại thời điểm tạo lịch trình.

### Có điểm đến rõ ràng

Ví dụ người dùng đang ở Đà Nẵng nhưng yêu cầu đi Hà Nội:

- Điểm đến được chỉ định (`Hà Nội`) là khu vực tìm địa điểm chính.
- GPS hiện tại không làm hệ thống lọc các địa điểm Hà Nội.
- GPS có thể được dùng làm điểm xuất phát/tham khảo nếu sau này bổ sung phần
  vận chuyển liên tỉnh.

### Không có điểm đến rõ ràng

Nếu chỉ có GPS mà không có thành phố:

- Backend tìm các địa điểm có tọa độ trong bán kính 50 km.
- Khoảng cách được tính bằng Haversine.
- Địa điểm gần vị trí hiện tại được cộng điểm ưu tiên.
- Nếu không có GPS và cũng không có điểm đến, hệ thống không giới hạn theo khu
  vực và trả warning.

Frontend lấy GPS qua `navigator.geolocation`. Nếu người dùng từ chối quyền,
trình duyệt không hỗ trợ hoặc request timeout, request vẫn được gửi mà không có
`current_location`.

## 6. Luồng tạo itinerary bằng LLM

Hàm trung tâm là
[`ItineraryGenerationService.generate_itinerary`](../apps/api/app/services/itinerary_generation_service.py).

### Bước 1: Kiểm tra thông tin tối thiểu

Cần có:

- Điểm đến chính hoặc điểm đến bổ sung.
- Số ngày, hoặc ngày bắt đầu và ngày kết thúc.

Nếu có điểm đến nhưng thiếu số ngày, hệ thống hiện mặc định 3 ngày. Nếu thiếu
điểm đến, response có trạng thái `NEED_MORE_INFORMATION`.

### Bước 2: Tìm địa điểm thực tế

`PlaceSearchService.search_places_for_itinerary`:

- Lọc địa điểm đã bị xóa.
- Lọc theo thành phố/điểm đến.
- Loại địa điểm bị loại trừ.
- Ưu tiên must-visit, preferred và sở thích.
- Tính điểm gần GPS nếu GPS được gửi.
- Trả tối đa 35 ứng viên cho bước sinh itinerary.

### Bước 3: Gom cụm địa lý

Các ứng viên có tọa độ được gom thành các cụm theo số ngày bằng thuật toán
chọn các hạt giống cách xa nhau nhất rồi gán mỗi địa điểm vào hạt giống gần
nhất.

Thông tin cụm được đưa vào prompt để LLM:

- Ưu tiên các địa điểm cùng cụm trong cùng ngày.
- Hạn chế trộn các khu vực xa nhau.
- Ưu tiên khoảng cách giữa hai địa điểm trong ngày không quá 15 km.

Đây là khoảng cách đường chim bay, không phải thời gian lái xe thực tế.

### Bước 4: Gọi LLM

LLM nhận:

- System prompt về quy tắc sinh itinerary.
- Context chuyến đi đã tổng hợp.
- Danh sách địa điểm thực tế và `place_id`.
- Cụm địa lý, giờ mở cửa, giá và tọa độ nếu có.
- `user_prompt` mới nhất.

LLM **không nhận toàn bộ lịch sử message trực tiếp** ở bước này. Lịch sử chat
được xử lý trước để tạo `TripPlanningContext`; các yêu cầu chưa được lưu trong
context cần nằm trong `user_prompt` để chắc chắn được áp dụng.

## 6.1. Cho LLM biết vị trí hiện tại trong luồng chat

Ngoài lúc tạo itinerary, frontend cũng gửi `current_location` trong cả hai
luồng hỏi đáp:

- `POST /api/v1/rag/ask`
- `POST /api/v1/rag/ask-stream`

Ví dụ:

```json
{
  "message": "Gợi ý quán ăn gần tôi",
  "mode": "chat",
  "current_location": {
    "latitude": 16.0544,
    "longitude": 108.2022
  }
}
```

Backend chèn tọa độ vào phần context gửi cho LLM. LLM biết đây là vị trí hiện
tại của người dùng và có thể dùng nó để trả lời theo ngữ cảnh. Tuy nhiên, tọa độ
chưa được reverse geocode trong backend; không được coi tọa độ là tên đường hoặc
địa chỉ chính xác nếu chưa có dịch vụ bản đồ xác nhận.

Frontend lấy GPS bằng `navigator.geolocation`. Nếu người dùng không cấp quyền,
request vẫn hoạt động nhưng không có thông tin vị trí. Vị trí chỉ được gửi
trong request hiện tại, không được lưu vào tin nhắn hoặc database.

### Bước 5: Parse và sửa JSON

LLM phải trả về một JSON có `days`. Backend hỗ trợ:

1. Parse JSON trực tiếp.
2. Parse JSON nằm trong code fence.
3. Trích JSON từ phần text bao quanh.
4. Gọi repair một lần nếu phản hồi không hợp lệ.

Nếu vẫn lỗi, response có trạng thái `FAILED`.

### Bước 6: Validate và sanitize

Backend kiểm tra:

- Đúng số ngày.
- `day_number` liên tục từ 1 đến N.
- `place_id` phải thuộc danh sách ứng viên.
- Không dùng địa điểm bị loại trừ.
- Must-visit phải được xếp hoặc ghi vào `unresolved_requirements`.
- `order_index` liên tục trong từng ngày.
- Giờ bắt đầu trước giờ kết thúc.
- Không chồng thời gian; hoạt động bị chồng sẽ được dịch chuyển.
- Chi phí, thời lượng và khoảng cách không âm.
- Ngày lịch đồng bộ với ngày bắt đầu chuyến đi.
- Khoảng cách lớn giữa các địa điểm trong cùng ngày được đưa vào `warnings`.

### Bước 7: Lưu database

Khi `save_to_db=true` và response hợp lệ, backend lưu:

```text
Trip
 └── ItineraryDay
      └── ItineraryActivity
```

Luồng persistence có rollback khi lỗi. Sinh lại lịch trình không được tạo
trùng các ngày/hoạt động cũ.

## 7. Response mẫu

```json
{
  "status": "GENERATED",
  "trip_id": 123,
  "title": "Đà Nẵng 3 ngày 2 đêm",
  "summary": "Lịch trình ưu tiên biển, ẩm thực và các địa điểm gần nhau.",
  "duration_days": 3,
  "currency": "VND",
  "budget": {
    "target_total": 5000000,
    "estimated_total": 1800000,
    "confidence": "ESTIMATED",
    "notes": []
  },
  "days": [
    {
      "day_number": 1,
      "date": "2026-11-01",
      "title": "Biển và trung tâm thành phố",
      "activities": [
        {
          "order_index": 1,
          "activity_type": "VISIT",
          "place_id": 42,
          "title": "Tham quan Bãi biển Mỹ Khê",
          "start_time": "08:00",
          "end_time": "10:00",
          "duration_minutes": 120,
          "estimated_cost": 0
        }
      ]
    }
  ],
  "warnings": [],
  "unresolved_requirements": [],
  "missing_information": []
}
```

Các trạng thái:

- `GENERATED`: đã sinh được lịch trình.
- `NEED_MORE_INFORMATION`: thiếu dữ liệu tối thiểu.
- `FAILED`: không tìm thấy ứng viên hoặc LLM không trả JSON hợp lệ.

## 8. Sử dụng trên Web

### Tạo trip mới

Trang [`apps/web/app/trips/new/page.tsx`](../apps/web/app/trips/new/page.tsx):

1. Người dùng nhập tên, thành phố, quốc gia và số ngày.
2. Frontend xin GPS hiện tại.
3. Frontend gọi `POST /api/v1/trips`.
4. Frontend gọi `POST /api/v1/trips/{id}/itinerary/generate`.
5. Sau khi thành công, chuyển tới `/trips/{id}`.

### Tạo từ chat

[`apps/web/hooks/useChat.ts`](../apps/web/hooks/useChat.ts) dùng context đang
được đồng bộ trong chat, lấy GPS hiện tại và gọi:

- `chatService.generateItinerary(tripId, options)`, hoặc
- `chatService.generateItineraryDirect(options)`.

## 9. Kiểm thử

Chạy các test liên quan tại `apps/api`:

```powershell
uv run python -m unittest tests.test_itinerary_generation -v
uv run python -m unittest tests.test_place_search -v
```

Kiểm tra syntax:

```powershell
uv run python -m py_compile app\services\itinerary_generation_service.py
```

Kiểm tra TypeScript frontend:

```powershell
cd ..\web
bunx tsc --noEmit
```

## 10. Giới hạn hiện tại và hướng mở rộng

- Khoảng cách gom cụm và validate là khoảng cách đường chim bay bằng Haversine.
- Chưa có routing API để tính quãng đường và thời gian lái xe thực tế.
- GPS hiện tại chưa tự động tạo chặng di chuyển liên tỉnh tới một điểm đến xa.
- Lịch sử chat không được truyền nguyên văn vào prompt itinerary; thông tin cần
  được trích xuất vào context hoặc gửi trong `user_prompt`.
- Nếu muốn bảo đảm mạnh hơn, có thể thêm routing API, giới hạn tổng thời gian
  di chuyển mỗi ngày và cơ chế tự động sửa lịch trình khi vượt giới hạn.
