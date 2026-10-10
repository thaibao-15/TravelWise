import asyncio
import os
import time
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app
from app.services.tts_service import BlazeTTSError, BlazeTTSService


class TestTTSRealtimeRoutesAndService(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_tts_status_endpoint(self):
        """Kiểm tra endpoint /api/v1/tts/status trả về đúng thông số cấu hình Realtime."""
        response = self.client.get("/api/v1/tts/status")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("is_configured", data)
        self.assertIn("speaker_id", data)
        self.assertEqual(data["model"], "2.0-realtime")
        self.assertEqual(data["audio_format"], "mp3")
        self.assertIn("ws_url", data)
        self.assertTrue(data["ws_url"].startswith("wss://"))

    def test_clean_text_markdown_stripping(self):
        """Kiểm tra hàm làm sạch văn bản loại bỏ markdown, link, code block."""
        raw_text = """### Tiêu đề
Đây là **Đà Nẵng** và [Cầu Rồng](https://example.com/cau-rong).
```python
print('hello')
```
* Bãi biển Mỹ Khê
- Chùa Linh Ứng
"""
        cleaned = BlazeTTSService.clean_text(raw_text)
        self.assertNotIn("```", cleaned)
        self.assertNotIn("https://", cleaned)
        self.assertNotIn("###", cleaned)
        self.assertIn("Đà Nẵng", cleaned)
        self.assertIn("Cầu Rồng", cleaned)
        self.assertIn("Bãi biển Mỹ Khê", cleaned)

    def test_tts_empty_text_validation(self):
        """Kiểm tra validation khi gửi văn bản rỗng."""
        res_post = self.client.post("/api/v1/tts", json={"text": ""})
        self.assertIn(res_post.status_code, (400, 422))

        res_get = self.client.get("/api/v1/tts/stream?text=")
        self.assertIn(res_get.status_code, (400, 422))

    def test_service_validation_without_key(self):
        """Kiểm tra ngoại lệ khi thiếu BLAZE_API_KEY."""
        service = BlazeTTSService(api_key="")
        with self.assertRaises(BlazeTTSError) as ctx:
            service.validate_configuration()
        self.assertEqual(ctx.exception.status_code, 401)

    def test_tts_stream_get_endpoint_mocked(self):
        """Kiểm tra GET /api/v1/tts/stream trả về audio/mpeg dạng stream."""
        async def mock_stream_speech(self_inst, text):
            yield b"\xff\xfb\x90\x44"  # MP3 frame header simulation
            yield b"\x00\x00\x00\x00"

        with patch.object(BlazeTTSService, "stream_speech", mock_stream_speech):
            response = self.client.get("/api/v1/tts/stream?text=Xin+chao+TravelWise")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers["content-type"], "audio/mpeg")
            self.assertEqual(response.content, b"\xff\xfb\x90\x44\x00\x00\x00\x00")

    def test_tts_post_endpoint_mocked(self):
        """Kiểm tra POST /api/v1/tts trả về audio/mpeg dạng stream."""
        async def mock_stream_speech(self_inst, text):
            yield b"MOCK_MP3_STREAM_CHUNKS"

        with patch.object(BlazeTTSService, "stream_speech", mock_stream_speech):
            response = self.client.post(
                "/api/v1/tts",
                json={"text": "Chào mừng bạn đến với TravelWise Đà Nẵng."},
            )
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers["content-type"], "audio/mpeg")
            self.assertEqual(response.content, b"MOCK_MP3_STREAM_CHUNKS")

    def test_live_realtime_websocket_if_configured(self):
        """Kiểm tra kết nối trực tiếp Blaze Realtime WebSocket (chạy khi có BLAZE_API_KEY)."""
        if not settings.BLAZE_API_KEY or not settings.BLAZE_API_KEY.strip():
            self.skipTest("BLAZE_API_KEY chưa cấu hình, bỏ qua test live.")

        service = BlazeTTSService()

        async def run_live_test():
            t0 = time.perf_counter()
            chunks = []
            ttfb = None

            async for chunk in service.stream_speech("Xin chào, đây là bài kiểm tra giọng đọc realtime."):
                if ttfb is None:
                    ttfb = (time.perf_counter() - t0) * 1000
                chunks.append(chunk)

            total_time = (time.perf_counter() - t0) * 1000
            total_bytes = sum(len(c) for c in chunks)
            return len(chunks), total_bytes, ttfb, total_time

        chunk_count, total_bytes, ttfb, total_time = asyncio.run(run_live_test())

        self.assertGreater(chunk_count, 0, "Must receive at least 1 audio chunk.")
        self.assertGreater(total_bytes, 1000, "Audio data must be > 1000 bytes.")
        self.assertIsNotNone(ttfb, "TTFB must not be None.")
        print(f"\n[Test Live Blaze Realtime TTS]: TTFB={ttfb:.0f}ms, TotalTime={total_time:.0f}ms, Chunks={chunk_count}, Bytes={total_bytes}")


if __name__ == "__main__":
    unittest.main()
