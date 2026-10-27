# TravelWise Realtime Voice Agent (LiveKit Worker, Blaze AI & Gemini RAG)

Tiến trình LiveKit Voice Agent chạy độc lập cho hệ thống TravelWise AI. Agent kết nối vào cụm máy chủ **LiveKit Cloud**, tự động được điều phối (dispatch) vào các phòng WebRTC khi người dùng kết nối từ Next.js và xử lý luồng âm thanh hai chiều toàn trình:
`WebRTC Audio (User)` → `Blaze STT` → `TravelWise Gemini + Chroma RAG` → `Blaze TTS` → `WebRTC Audio (Speaker)`.

---

## 1. Kiến Trúc & Vai Trò

- **Độc lập hoàn toàn với FastAPI**: Không chạy realtime WebSocket WebRTC trong process của API server, giữ cho backend gọn nhẹ và dễ mở rộng.
- **Tên Agent điều phối (`agent_name`)**: `travelwise-voice-assistant` (khớp với cấu hình trong `apps/api/.env` và token cấp từ backend).
- **Tái sử dụng trọn vẹn Gemini + Chroma RAG hiện tại**:
  - Gọi nội bộ đến service backend (`/api/v1/rag/ask` hoặc `/api/v1/rag/ask-stream`) với chế độ `mode="voice"`.
  - Giữ nguyên system prompt TravelWise, toàn bộ tri thức du lịch Đà Nẵng, quy tắc chống bịa đặt (grounding), trích xuất ngữ cảnh kế hoạch chuyến đi và tóm tắt hội thoại.
  - Tự động tạo token JWT dịch vụ nội bộ từ `JWT_SECRET` tương ứng với `user_id` của người tham gia để bảo đảm kiểm soát quyền sở hữu cuộc trò chuyện và lưu lịch sử vào cùng cơ sở dữ liệu SQL Server.
- **Tích hợp Blaze AI STT/TTS tùy chỉnh**:
  - `blaze.BlazeSTT`: Subclass của `livekit.agents.stt.STT` kết nối WebSocket `wss://api.blaze.vn/v1/stt/realtime` (model `stt-stream-1.5`, tiếng Việt `vi`, 16kHz PCM mono). Tự động resample audio từ WebRTC sang 16kHz và emit `SpeechEvent.INTERIM_TRANSCRIPT` / `FINAL_TRANSCRIPT`.
  - `blaze.BlazeTTS`: Subclass của `livekit.agents.tts.TTS` kết nối WebSocket `wss://api.blaze.vn/v1/tts/realtime` (speaker `DaNang-Nu-1-BL`, model `2.0-realtime`, speed `1.5`, audio format `mp3`). Sử dụng zero-roundtrip pipelining và decode MP3 trực tiếp thành các PCM `rtc.AudioFrame` 24kHz bằng `livekit.agents.utils.codecs.AudioStreamDecoder`.
- **Luồng dữ liệu WebRTC**:
  1. Người dùng kết nối vào phòng từ Next.js (`/livekit-test` hoặc `/voice-guide`).
  2. LiveKit Cloud tự động gửi Job dispatch cho Agent Worker.
  3. Agent tham gia phòng, publish Audio Track 24kHz Mono, và bắt đầu lắng nghe Audio Track từ người dùng.
  4. Agent gửi âm thanh người dùng vào Blaze STT, nhận diện tiếng Việt.
  5. Agent gửi transcript đến hệ thống Gemini/RAG của TravelWise để truy xuất tài liệu và tạo câu trả lời đàm thoại (văn xuôi tự nhiên, không markdown, 3-4 câu).
  6. Agent tổng hợp câu phản hồi qua Blaze TTS và stream âm thanh về trình duyệt qua WebRTC.

---

## 2. Cài Đặt Môi Trường

### Yêu cầu hệ thống
- Python `>= 3.10` (Khuyên dùng Python 3.14).
- Trình quản lý gói `uv` (hoặc `pip` / `venv`).

### Cài đặt dependencies:
```powershell
cd e:\TravelWise\apps\voice-agent
uv sync
```

---

## 3. Cấu Hình Biến Môi Trường

Tạo file `.env` trong thư mục `apps/voice-agent/` (hoặc Agent sẽ tự động nạp từ `apps/api/.env`):

```env
# LiveKit Cloud
LIVEKIT_URL=wss://travewise-yi9ty5dg.livekit.cloud
LIVEKIT_API_KEY=your_api_key_here
LIVEKIT_API_SECRET=your_api_secret_here
LIVEKIT_AGENT_NAME=travelwise-voice-assistant
LOG_LEVEL=INFO

# Blaze AI STT
BLAZE_API_KEY=your_blaze_api_key_here
BLAZE_STT_WS_URL=wss://api.blaze.vn/v1/stt/realtime
BLAZE_STT_MODEL=stt-stream-1.5
BLAZE_STT_LANGUAGE=vi
BLAZE_STT_SAMPLE_RATE=16000

# Blaze AI TTS
BLAZE_TTS_WS_URL=wss://api.blaze.vn/v1/tts/realtime
BLAZE_TTS_SPEAKER_ID=DaNang-Nu-1-BL
BLAZE_TTS_MODEL=2.0-realtime
BLAZE_TTS_SPEED=1.5
BLAZE_TTS_AUDIO_QUALITY=64
BLAZE_TTS_AUDIO_FORMAT=mp3
BLAZE_TTS_NORMALIZATION=basic

# Backend FastAPI RAG & Internal Security
BACKEND_API_URL=http://127.0.0.1:8000
JWT_SECRET=your-secret-key-must-match-api-jwt-secret
JWT_ALGORITHM=HS256
```

---

## 4. Hướng Dẫn Khởi Chạy

### Chế độ phát triển (Development / Local Console):
Lệnh chạy có chức năng tự động reload khi sửa code, phù hợp khi test trên máy dev:
```powershell
uv run python main.py dev
```

### Chế độ sản xuất (Production Worker Daemon):
Chế độ worker chịu tải thật, tự động duy trì kết nối WebSocket tới LiveKit Cloud:
```powershell
uv run python main.py start
```

### Chạy bằng Docker / Docker Compose:
```bash
# Chạy riêng container Voice Agent từ thư mục gốc dự án:
docker compose up -d --build voice-agent

# Xem log hoạt động:
docker compose logs -f voice-agent
```

### Quy trình kiểm thử kết nối toàn trình (End-to-End Checklist):
1. **Khởi động Backend FastAPI**: Đảm bảo `apps/api` đang chạy ở cổng `8000` (`uv run uvicorn app.main:app --reload`).
2. **Khởi động Voice Agent**: Chạy `uv run python main.py dev` trong thư mục `apps/voice-agent`. Console sẽ hiển thị:
   ```text
   Khởi động TravelWise Voice Agent Worker...
   Tên đăng ký Agent: travelwise-voice-assistant
   ```
3. **Mở trình duyệt Web**: Truy cập `http://localhost:3000/voice-guide` và bắt đầu nói vào micro. Voice Agent sẽ tự động tham gia phòng thoại và phản hồi trực tiếp.

### Chạy toàn bộ Unit & Integration Tests:
```powershell
uv run python -m unittest discover -s tests -p "test_*.py" -v
```

### Đo kiểm độ trễ toàn trình (E2E Voice Pipeline):
```powershell
uv run python tests/benchmark_rag_voice.py
```


---

## 5. Kết Quả Đo Kiểm Toàn Trình Thực Tế (E2E Benchmark)

| Lượt hội thoại | Câu hỏi kiểm thử | RAG Query Time | TTS Time to First Byte | **Độ trễ toàn trình (End-to-End)** |
|---|---|---|---|---|
| **Lượt 1** (Khởi tạo) | *"Cầu Rồng Đà Nẵng phun lửa vào ngày nào và mấy giờ?"* | 2,447 ms | 1,096 ms | **~3.5 s** |
| **Lượt 2** (Follow-up ngữ cảnh) | *"Nó có gần chợ đêm Sơn Trà không?"* | 2,712 ms | 995 ms | **~3.7 s** |
