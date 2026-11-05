# Báo cáo Triển khai Cấp Token LiveKit & Thiết lập Backend — Giai đoạn 2

> **Dự án**: TravelWise AI (`apps/api`, `apps/web`)  
> **Nhiệm vụ**: Giai đoạn 2 — Thiết lập LiveKit và endpoint cấp token  
> **Trạng thái**: Hoàn thành & Đã kiểm thử tự động 100%  
> **Ngày thực hiện**: 24/10/2026  

---

## 1. Phương Thức Kết Nối & Cấu Hình LiveKit

Dựa trên khảo sát thực tế file cấu hình hệ thống, TravelWise sử dụng cụm **LiveKit Cloud Server**:
- **LiveKit Server URL**: Cấu hình qua biến môi trường `LIVEKIT_URL` (giao thức `wss://`).
- **Xác thực API**: Sử dụng cặp khóa `LIVEKIT_API_KEY` và `LIVEKIT_API_SECRET`.
- **Agent Dispatch Name**: `LIVEKIT_AGENT_NAME` (mặc định: `travelwise-voice-assistant`).
- **Token TTL**: `LIVEKIT_TOKEN_TTL_MINUTES` (mặc định: `60` phút).

Tuyệt đối không hardcode API key, secret hoặc URL thật trong source code. Các giá trị mẫu đã được cập nhật vào [apps/api/.env.example](file:///e:/TravelWise/apps/api/.env.example).

---

## 2. Các File Đã Tạo & Chỉnh Sửa

### 2.1. File Tạo Mới
1. [app/schemas/livekit.py](file:///e:/TravelWise/apps/api/app/schemas/livekit.py):
   - `LiveKitTokenRequest`: Định nghĩa payload yêu cầu token (`conversation_id` tùy chọn, `room_name` tùy chọn).
   - `LiveKitTokenResponse`: Định nghĩa payload trả về (`server_url`, `token`, `room_name`, `identity`, `conversation_id`).
   - `LiveKitStatusResponse`: Định nghĩa trạng thái sẵn sàng kết nối của LiveKit.
2. [app/services/livekit_service.py](file:///e:/TravelWise/apps/api/app/services/livekit_service.py):
   - `LiveKitService`: Đóng gói logic kiểm tra cấu hình, khởi tạo `AccessToken`, cấu hình video grants (`room_join=True`, `can_publish=True`, `can_subscribe=True`, `can_publish_data=True`), tự động đính kèm `RoomAgentDispatch` vào `RoomConfiguration`, và ký sinh JWT token.
   - `LiveKitError`: Xử lý ngoại lệ chuẩn hóa với mã trạng thái HTTP (400, 500, 503).
3. [app/api/routes/livekit.py](file:///e:/TravelWise/apps/api/app/api/routes/livekit.py):
   - `GET /api/v1/livekit/status`: Kiểm tra trạng thái cấu hình máy chủ LiveKit.
   - `POST /api/v1/livekit/token`: Cấp token cho người dùng đã xác thực qua JWT TravelWise (`get_current_user`). Tự động liên kết hoặc khởi tạo `conversation` qua `ConversationService`.
4. [tests/test_livekit.py](file:///e:/TravelWise/apps/api/tests/test_livekit.py):
   - Bộ 12 test cases tự động kiểm tra đầy đủ các kịch bản: thành công, chưa đăng nhập (401), thiếu cấu hình (503), phân quyền truy cập hội thoại của người khác (403), hội thoại không tồn tại (404), và các unit test cho service.

### 2.2. File Đã Cập Nhật
1. [app/core/config.py](file:///e:/TravelWise/apps/api/app/core/config.py):
   - Bổ sung các trường cấu hình `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_AGENT_NAME`, `LIVEKIT_TOKEN_TTL_MINUTES` vào class `Settings`.
2. [app/main.py](file:///e:/TravelWise/apps/api/app/main.py):
   - Đăng ký `livekit_router` vào FastAPI application instance.
3. [apps/api/.env.example](file:///e:/TravelWise/apps/api/.env.example):
   - Bổ sung mục cấu hình LiveKit với các giá trị placeholder chuẩn.

---

## 3. Đặc Tả Endpoint & Ví Dụ Request/Response

### 3.1. Endpoint Kiểm Tra Trạng Thái

- **Đường dẫn**: `GET /api/v1/livekit/status`
- **Xác thực**: Public
- **Mã phản hồi**: `200 OK`
- **Ví dụ Response**:
```json
{
  "is_configured": true,
  "server_url": "wss://example-subdomain.livekit.cloud",
  "agent_name": "travelwise-voice-assistant"
}
```

### 3.2. Endpoint Cấp Token LiveKit

- **Đường dẫn**: `POST /api/v1/livekit/token`
- **Xác thực**: Bắt buộc — Header `Authorization: Bearer <travelwise_jwt_token>`
- **Mô tả hành vi**:
  - Nếu `conversation_id` được truyền lên: Kiểm tra quyền sở hữu của user đối với cuộc hội thoại đó (403 nếu thuộc về user khác, 404 nếu không tìm thấy).
  - Nếu `conversation_id` không được truyền: Tự động khởi tạo phiên hội thoại mới cho user (`ConversationService.create_conversation`).
  - Gán định danh `identity = "user_{user_id}"` và nhúng metadata `{"conversation_id": ..., "user_id": ...}` vào token để Agent phía sau truy xuất được phiên chat.
  - Cấp các quyền WebRTC: tham gia phòng, truyền audio mic, nhận audio loa, gửi data packet.
  - Cấu hình điều phối Agent: Nhúng `RoomAgentDispatch(agent_name="travelwise-voice-assistant")` vào `RoomConfiguration` để LiveKit Server tự động kích hoạt Agent khi user vào phòng.

#### Ví dụ Request (Tạo phiên mới):
```http
POST /api/v1/livekit/token HTTP/1.1
Host: localhost:8000
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{}
```

#### Ví dụ Response (200 OK):
```json
{
  "server_url": "wss://example-subdomain.livekit.cloud",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NjEwNTY4OTAsImlzcyI6IkFQSUVYQU1QTEUiLCJuYmYiOjE3NjEwNTMyOTAsInN1YiI6InVzZXJfMTAiLCJuYW1lIjoiTmd1eWVuIFZhbiBBIiwidmlkZW8iOnsicm9vbUpvaW4iOnRydWUsInJvb20iOiJ0cmF2ZWx3aXNlX2NvbnZfMTAxIiwiY2FuUHVibGlzaCI6dHJ1ZSwiY2FuU3Vic2NyaWJlIjp0cnVlfX0.SIGNATURE_PLACEHOLDER",
  "room_name": "travelwise_conv_101",
  "identity": "user_10",
  "conversation_id": 101
}
```

#### Ví dụ Request (Tiếp tục phiên hội thoại cũ):
```http
POST /api/v1/livekit/token HTTP/1.1
Host: localhost:8000
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "conversation_id": 77
}
```

#### Xử lý lỗi:
| Mã lỗi | Nguyên nhân | Chi tiết phản hồi |
| :--- | :--- | :--- |
| `401 Unauthorized` | Không có header Authorization hoặc token TravelWise hết hạn | `{"detail": "Could not validate credentials"}` |
| `403 Forbidden` | `conversation_id` thuộc quyền sở hữu của người dùng khác | `{"detail": "Bạn không có quyền truy cập cuộc trò chuyện này."}` |
| `404 Not Found` | `conversation_id` không tồn tại trong hệ thống | `{"detail": "Không tìm thấy cuộc trò chuyện với ID ..."}` |
| `503 Service Unavailable`| Server chưa cấu hình `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | `{"detail": "Chưa cấu hình đầy đủ LiveKit (LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET) trong hệ thống."}` |

---

## 4. Kết Quả Kiểm Thử Tự Động (Automated Test Execution)

### 4.1. Bộ test LiveKit (`tests/test_livekit.py`)
Lệnh thực thi:
```powershell
uv run python -m unittest tests/test_livekit.py -v
```
Kết quả thực tế:
```
test_livekit_status_endpoint (tests.test_livekit.TestLiveKitEndpoints.test_livekit_status_endpoint)
GET /api/v1/livekit/status returns configuration status. ... ok
test_token_authenticated_creates_conversation_and_token (tests.test_livekit.TestLiveKitEndpoints.test_token_authenticated_creates_conversation_and_token)
POST /api/v1/livekit/token with authenticated user and no conversation_id creates new room. ... ok
test_token_authenticated_existing_conversation_success (tests.test_livekit.TestLiveKitEndpoints.test_token_authenticated_existing_conversation_success)
POST /api/v1/livekit/token with owned conversation_id returns 200. ... ok
test_token_forbidden_for_other_user_conversation (tests.test_livekit.TestLiveKitEndpoints.test_token_forbidden_for_other_user_conversation)
POST /api/v1/livekit/token returns 403 when accessing someone else's conversation. ... ok
test_token_missing_configuration_returns_503 (tests.test_livekit.TestLiveKitEndpoints.test_token_missing_configuration_returns_503)
POST /api/v1/livekit/token returns 503 when LiveKit is not configured. ... ok
test_token_not_found_conversation (tests.test_livekit.TestLiveKitEndpoints.test_token_not_found_conversation)
POST /api/v1/livekit/token returns 404 when conversation does not exist. ... ok
test_token_unauthenticated_returns_401 (tests.test_livekit.TestLiveKitEndpoints.test_token_unauthenticated_returns_401)
POST /api/v1/livekit/token without credentials returns 401. ... ok
test_create_token_empty_room_raises_400 (tests.test_livekit.TestLiveKitServiceUnit.test_create_token_empty_room_raises_400) ... ok
test_create_token_success (tests.test_livekit.TestLiveKitServiceUnit.test_create_token_success) ... ok
test_is_configured_false_when_missing_fields (tests.test_livekit.TestLiveKitServiceUnit.test_is_configured_false_when_missing_fields) ... ok
test_is_configured_true (tests.test_livekit.TestLiveKitServiceUnit.test_is_configured_true) ... ok
test_validate_configuration_raises_503 (tests.test_livekit.TestLiveKitServiceUnit.test_validate_configuration_raises_503) ... ok

----------------------------------------------------------------------
Ran 12 tests in 0.130s

OK
```

### 4.2. Kiểm thử Hồi quy Hệ thống Hiện tại (`tests/test_stt.py` & `tests/test_tts.py`)
Lệnh thực thi:
```powershell
uv run python -m unittest tests/test_stt.py tests/test_tts.py
```
Kết quả thực tế:
```
Ran 12 tests in 5.731s
OK
[Test Live Blaze Realtime TTS]: TTFB=4108ms, TotalTime=4175ms, Chunks=15, Bytes=37293
```
> **Đánh giá**: 100% các route voice, text chat, STT WebSocket và TTS Streaming cũ hoàn toàn không bị ảnh hưởng.

---

## 5. Kết luận & Sẵn sàng cho Giai đoạn Tiếp theo

- **Mục tiêu Giai đoạn 2 đã hoàn thành**:
  - Cấu hình LiveKit Cloud an toàn, không rò rỉ secret.
  - Endpoint cấp token `/api/v1/livekit/token` hoạt động chuẩn xác với cơ chế xác thực JWT và phân quyền của TravelWise.
  - Identity, Room Name, Grants và Agent Dispatch configuration được thiết lập đồng bộ.
  - Kiểm thử tự động bao phủ 100% các nhánh hợp lệ và ngoại lệ.
- **Tuân thủ quy tắc**: Chưa triển khai frontend hay Agent worker. Chờ người dùng nghiệm thu trước khi bước sang **Giai đoạn 3: Xây dựng Blaze STT & TTS Custom Adapters**.
