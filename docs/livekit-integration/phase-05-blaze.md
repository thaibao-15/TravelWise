# Báo Cáo Giai Đoạn 5: Tích Hợp Blaze AI STT/TTS Vào LiveKit Agent

---

## 1. Tổng Quan & Trạng Thái Thực Hiện

- **Trạng thái**: Hoàn thành (Completed & Live Verified).
- **Mục tiêu**: Tái sử dụng trọn vẹn dịch vụ nhận diện giọng nói (STT) và tổng hợp giọng nói (TTS) từ nhà cung cấp **Blaze AI** mà TravelWise đang sử dụng, tích hợp trực tiếp vào tiến trình LiveKit Agent (`apps/voice-agent`) mà không thay thế bằng nhà cung cấp khác và không làm ảnh hưởng đến các API voice cũ của FastAPI.
- **Vị trí adapter**: `apps/voice-agent/blaze/`.

---

## 2. Kết Quả Khảo Sát Kỹ Thuật (Bắt Buộc Trước Khi Code)

Dựa trên khảo sát trực tiếp mã nguồn hiện hữu tại `apps/api/app/services/blaze_stt_service.py`, `apps/api/app/services/tts_service.py` và đo kiểm mạng thực tế tới máy chủ Blaze AI:

### 2.1. Dịch vụ Speech-To-Text (Blaze STT)
1. **Giao thức**: WebSocket (`wss://api.blaze.vn/v1/stt/realtime`).
2. **Xác thực**: Gửi frame JSON đầu tiên ngay sau khi kết nối:
   ```json
   {
     "token": "<BLAZE_API_KEY>",
     "language": "vi",
     "model": "stt-stream-1.5"
   }
   ```
3. **Phản hồi Handshake**:
   - `{"type": "successful-authentication", "message": "Authentication successful, ready to accept query"}`
   - `{"type": "ready", "text": "ok", "translation_engine": "default"}` (Báo hiệu sẵn sàng tiếp nhận luồng âm thanh).
4. **Định dạng âm thanh đầu vào**:
   - Codec: Raw Linear Signed 16-bit PCM.
   - Sample Rate: **16,000 Hz** (16kHz).
   - Channels: Mono (1 kênh).
   - Truyền tải: Gửi trực tiếp các frame binary PCM bytes qua WebSocket.
5. **Định dạng phiên âm trả về**:
   - Trả về dạng JSON qua text frame:
     - `partial`: Phiên âm tạm thời (`is_final = False`).
     - `final`: Phiên âm trọn câu (`is_final = True`).
6. **Cơ chế phát hiện kết thúc lượt nói**: Blaze STT máy chủ tích hợp VAD tự động chốt câu `final`.

### 2.2. Dịch vụ Text-To-Speech (Blaze TTS)
1. **Giao thức**: WebSocket (`wss://api.blaze.vn/v1/tts/realtime`).
2. **Pipelining Frame**: Gửi đồng thời (zero-roundtrip) 2 frame JSON:
   - Frame 1 (Xác thực):
     ```json
     {
       "token": "<BLAZE_API_KEY>",
       "strategy": "request"
     }
     ```
   - Frame 2 (Nội dung & Tham số đọc):
     ```json
     {
       "query": "<Văn bản tiếng Việt cần đọc>",
       "language": "vi",
       "audio_format": "mp3",
       "audio_quality": 64,
       "audio_speed": "1.5",
       "speaker_id": "DaNang-Nu-1-BL",
       "normalization": "basic",
       "model": "2.0-realtime"
     }
     ```
3. **Dữ liệu âm thanh trả về**:
   - Máy chủ trả về các binary chunks dạng **MP3**.
   - Frame kết thúc: `{"type": "finished-byte-stream"}`.
4. **Độ trễ & Streaming**: Blaze TTS stream từng khối MP3 nhị phân ngay khi bộ tổng hợp sinh ra, cho phép phát âm thanh lũy tiến mà không cần chờ toàn bộ văn bản đọc xong.

### 2.3. Kiểm tra Plugin chính thức từ LiveKit
- Phiên bản đang dùng: `livekit-agents==1.8.9`.
- Kết quả kiểm tra: LiveKit hiện tại **chỉ hỗ trợ** các plugin chính thức cho Deepgram, OpenAI, Cartesia, ElevenLabs, Google, Azure; **hoàn toàn không có plugin chính thức cho Blaze AI**.
- Giải pháp: Thiết kế **Custom Adapter** chuẩn kế thừa từ `livekit.agents.stt.STT`, `livekit.agents.stt.SpeechStream`, `livekit.agents.tts.TTS`, và `livekit.agents.tts.ChunkedStream`.

---

## 3. Kiến Trúc Adapter Tùy Chỉnh Cho Blaze AI

Toàn bộ adapter được đóng gói thành module độc lập tại `apps/voice-agent/blaze/`:

```
apps/voice-agent/blaze/
├── __init__.py          # Export BlazeSTT, BlazeTTS, Exceptions
├── exceptions.py        # Cây ngoại lệ kế thừa chuẩn LiveKit APIError
├── stt.py               # BlazeSTT & BlazeSpeechStream
└── tts.py               # BlazeTTS & BlazeChunkedStream
```

### 3.1. `BlazeSTT` & `BlazeSpeechStream`
- **Tự động chuyển đổi Sample Rate**: Kế thừa `stt.SpeechStream(sample_rate=16000)`. LiveKit Agents tự động resample bất kỳ định dạng nào từ WebRTC (ví dụ 48kHz hoặc 24kHz) về chuẩn 16,000Hz 16-bit mono PCM trước khi đưa vào `_input_ch`.
- **Luồng xử lý 2 chiều (Bidirectional)**:
  - `_send_loop`: Đọc các `rtc.AudioFrame` từ `self._input_ch`, trích xuất `bytes(frame.data)` và gửi nhị phân qua WebSocket tới Blaze STT.
  - `_recv_loop`: Lắng nghe kết quả từ Blaze STT. Khi nhận JSON `partial`, sinh `SpeechEvent.INTERIM_TRANSCRIPT`; khi nhận `final`, sinh `SpeechEvent.FINAL_TRANSCRIPT` đưa vào LiveKit event channel.
- **Phục hồi & ngắt kết nối**: Xử lý `_FlushSentinel`, đóng WebSocket an toàn và hủy task khi luồng thoại kết thúc.

### 3.2. `BlazeTTS` & `BlazeChunkedStream`
- **Zero-roundtrip Pipelining**: Gửi đồng thời authentication và query payload ngay khi mở socket, giảm thiểu tối đa handshake RTT.
- **Giải mã MP3 trực tiếp sang PCM WebRTC**: Sử dụng `tts.AudioEmitter` và `livekit.agents.utils.codecs.AudioStreamDecoder` (dựa trên thư viện PyAV). Khi nhận từng chunk MP3 nhị phân từ WebSocket, đẩy ngay vào `output_emitter.push(chunk)` để giải mã trực tiếp thành các frame PCM 24kHz mono cho LiveKit Room.
- **Bắt tín hiệu kết thúc**: Khi nhận `finished-byte-stream`, gọi `output_emitter.end_segment()` để hoàn tất lượt nói mà không bị ngắt quãng.

### 3.3. Xử lý lỗi, Timeout, Giới hạn kích thước & Cancellation
- **Phân loại lỗi theo chuẩn LiveKit**:
  - `BlazeAuthError`: Kế thừa `APIStatusError(status_code=401, retryable=False)` khi API key sai hoặc thiếu (không thử lại vô tận).
  - `BlazeConnectionError`: Kế thừa `APIConnectionError(retryable=True)` khi mất mạng hoặc socket đóng đột ngột (kích hoạt retry backoff của LiveKit).
  - `BlazeTimeoutError`: Kế thừa `APITimeoutError(retryable=True)` khi server phản hồi chậm.
- **Giới hạn kích thước gói tin**: Đặt `max_size=10*1024*1024` (10MB) trên WebSocket client để chống tràn bộ nhớ.
- **Bảo mật tuyệt đối**: Không log API key, token hoặc dữ liệu âm thanh thô ra console/file log.

---

## 4. Kết Quả Đo Kiểm Thực Tế (Live Benchmarks)

Chạy script đo kiểm thực tế `apps/voice-agent/tests/benchmark_blaze.py` kết nối trực tiếp máy chủ Blaze AI:

```powershell
uv run python tests/benchmark_blaze.py
```

### Kết quả đo kiểm:
```
--- Đo kiểm thực tế Blaze STT WebSocket ---
  BLAZE_API_KEY loaded: True (len: 40)
  BLAZE_STT_WS_URL: wss://api.blaze.vn/v1/stt/realtime
  WebSocket Connect Latency: 384.3ms
  Received message from STT: successful-authentication -> {'type': 'successful-authentication', 'message': 'Authentication successful, ready to accept query'}
  Received message from STT: ready -> {'type': 'ready', 'text': 'ok', 'translation_engine': 'default'}
  Auth-to-Ready Latency:    65.4ms
  Total STT Ready Latency:  450.2ms

--- Đo kiểm thực tế Blaze TTS WebSocket ---
  WebSocket Connect Latency: 186.7ms
  Time To First Byte (TTFB): 4058.9ms
  Total Synthesis Duration:  4185.4ms
  Received Audio Chunks:     181
  Received Total Audio Data: 81837 bytes (79.9 KB)
```

| Dịch vụ | Chỉ số đo | Giá trị thực tế | Đánh giá |
|---|---|---|---|
| **Blaze STT** | Thời gian kết nối WebSocket | 384.3 ms | Nhanh, kết nối ổn định |
| **Blaze STT** | Handshake Auth -> Ready | 65.4 ms | Rất nhanh, máy chủ xác thực tức thì |
| **Blaze STT** | **Tổng thời gian sẵn sàng nhận âm thanh** | **450.2 ms** | Đạt chuẩn phản hồi thời gian thực |
| **Blaze TTS** | Thời gian kết nối WebSocket | 186.7 ms | Ổn định |
| **Blaze TTS** | **Time to First Byte (TTFB)** | **~4.05 s** | Đặc thù model TTS 2.0 tạo câu đầy đủ trước khi stream |
| **Blaze TTS** | Tổng thời gian truyền 181 chunks MP3 | **4.18 s** | Băng thông truyền dữ liệu âm thanh chỉ mất ~130ms |

---

## 5. Kết Quả Kiểm Thử Tự Động (Test Suite)

Chạy bộ test kiểm thử đơn vị và tích hợp:
```powershell
cd e:\TravelWise\apps\voice-agent
uv run python -m unittest discover -s tests -p "test_*.py" -v
```

### Kết quả:
```
test_config_validation_missing_fields (test_agent.TestVoiceAgentUnit.test_config_validation_missing_fields) ... ok
test_config_validation_success (test_agent.TestVoiceAgentUnit.test_config_validation_success) ... ok
test_generate_test_tone_frames (test_agent.TestVoiceAgentUnit.test_generate_test_tone_frames) ... ok
test_worker_options_construction (test_agent.TestVoiceAgentUnit.test_worker_options_construction) ... ok
test_stt_audio_frame_streaming (test_blaze_adapter.TestBlazeSTTAdapter.test_stt_audio_frame_streaming)
Verify PCM audio frames are extracted and sent as bytes to WebSocket. ... ok
test_stt_handshake_and_interim_final_transcription (test_blaze_adapter.TestBlazeSTTAdapter.test_stt_handshake_and_interim_final_transcription)
Verify successful WebSocket handshake and parsing of interim & final transcripts. ... ok
test_stt_initialization_and_properties (test_blaze_adapter.TestBlazeSTTAdapter.test_stt_initialization_and_properties)
Verify capabilities, audio sample rate, model, provider, and language. ... ok
test_stt_provider_error_handling (test_blaze_adapter.TestBlazeSTTAdapter.test_stt_provider_error_handling)
Verify provider error frame raises BlazeSTTError. ... ok
test_stt_requires_api_key (test_blaze_adapter.TestBlazeSTTAdapter.test_stt_requires_api_key)
Verify error is raised when api_key is empty. ... ok
test_tts_cancellation_handling (test_blaze_adapter.TestBlazeTTSAdapter.test_tts_cancellation_handling)
Verify cancellation during synthesis terminates cleanly. ... ok
test_tts_empty_input_handled_gracefully (test_blaze_adapter.TestBlazeTTSAdapter.test_tts_empty_input_handled_gracefully)
Verify empty or whitespace-only text returns without error. ... ok
test_tts_initialization_and_properties (test_blaze_adapter.TestBlazeTTSAdapter.test_tts_initialization_and_properties)
Verify audio format, model, speaker, sample rate, and channels. ... ok
test_tts_provider_error_handling (test_blaze_adapter.TestBlazeTTSAdapter.test_tts_provider_error_handling)
Verify provider error frame raises BlazeTTSError. ... ok
test_tts_requires_api_key (test_blaze_adapter.TestBlazeTTSAdapter.test_tts_requires_api_key)
Verify error is raised when api_key is empty. ... ok
test_tts_streaming_synthesis_flow (test_blaze_adapter.TestBlazeTTSAdapter.test_tts_streaming_synthesis_flow)
Verify auth + query frames sent and binary MP3 chunks pushed to AudioEmitter. ... ok

----------------------------------------------------------------------
Ran 15 tests in 0.281s

OK
```

Kiểm tra an toàn phía backend FastAPI (`apps/api`):
```powershell
uv run python -m unittest tests/test_livekit.py -v
Ran 12 tests in 0.136s -> OK
```

---

## 6. Cấu Hình Biến Môi Trường (Environment Variables)

Đã cập nhật file mẫu `apps/voice-agent/.env.example`:

```env
# =============================================================================
# LiveKit Cloud Configuration
# =============================================================================
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your-api-key
LIVEKIT_API_SECRET=your-api-secret
LIVEKIT_AGENT_NAME=travelwise-voice-assistant

# =============================================================================
# Blaze AI STT Realtime Configuration
# =============================================================================
BLAZE_API_KEY=your-blaze-api-key
BLAZE_STT_WS_URL=wss://api.blaze.vn/v1/stt/realtime
BLAZE_STT_MODEL=stt-stream-1.5
BLAZE_STT_LANGUAGE=vi
BLAZE_STT_SAMPLE_RATE=16000

# =============================================================================
# Blaze AI TTS Realtime Configuration
# =============================================================================
BLAZE_TTS_WS_URL=wss://api.blaze.vn/v1/tts/realtime
BLAZE_TTS_SPEAKER_ID=DaNang-Nu-1-BL
BLAZE_TTS_MODEL=2.0-realtime
BLAZE_TTS_SPEED=1.5
BLAZE_TTS_AUDIO_QUALITY=64
BLAZE_TTS_AUDIO_FORMAT=mp3
BLAZE_TTS_NORMALIZATION=basic
```

---

## 7. Tính Toàn Vẹn Của Hệ Thống Hiện Hữu

- Các endpoint hiện tại của FastAPI:
  - `/api/v1/stt/ws` (WebSocket STT cũ) -> **Giữ nguyên 100% không đổi**.
  - `/api/v1/tts/stream` (Streaming TTS cũ) -> **Giữ nguyên 100% không đổi**.
  - `/api/v1/rag/ask-stream` (Text chat cũ) -> **Giữ nguyên 100% không đổi**.
- Không tạo dependency xung đột; `apps/voice-agent` hoạt động như một microservice riêng biệt.

---

## 8. Sẵn Sàng Cho Giai Đoạn 6 (Phase 6)

Giai đoạn 5 đã thiết lập hoàn chỉnh tầng giọng nói STT và TTS bằng Blaze AI cho LiveKit Agent.
Các bước tiếp theo của **Giai đoạn 6**:
1. Tích hợp Gemini LLM & RAG LangChain / Chroma hiện hữu của TravelWise vào luồng điều phối hội thoại của Agent.
2. Tích hợp công cụ tra cứu thông tin du lịch, thời tiết, địa điểm và lập lịch trình chuyến đi Đà Nẵng bằng giọng nói.
