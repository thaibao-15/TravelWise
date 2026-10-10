import asyncio
import hashlib
import json
import logging
import re
from typing import AsyncGenerator, Optional

import websockets
from websockets.exceptions import ConnectionClosed, WebSocketException

from app.core.config import settings

logger = logging.getLogger(__name__)


class BlazeTTSError(Exception):
    """Base exception for Blaze TTS operations."""

    def __init__(self, message: str, status_code: int = 500):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class BlazeTTSService:
    """Service to handle Realtime Text-to-Speech synthesis with Blaze AI via WebSocket."""

    _audio_cache: dict[str, bytes] = {}

    def __init__(
        self,
        api_key: Optional[str] = None,
        ws_url: Optional[str] = None,
        speaker_id: Optional[str] = None,
        model: Optional[str] = None,
        speed: Optional[str] = None,
        audio_format: Optional[str] = None,
        audio_quality: Optional[int] = None,
        normalization: Optional[str] = None,
        language: Optional[str] = None,
    ):
        self.api_key = api_key if api_key is not None else settings.BLAZE_API_KEY
        self.ws_url = ws_url or getattr(settings, "BLAZE_TTS_WS_URL", "wss://api.blaze.vn/v1/tts/realtime")
        self.speaker_id = speaker_id or settings.BLAZE_TTS_SPEAKER_ID
        self.model = model or settings.BLAZE_TTS_MODEL
        self.speed = speed or settings.BLAZE_TTS_SPEED
        self.audio_format = audio_format or settings.BLAZE_TTS_AUDIO_FORMAT
        self.audio_quality = audio_quality or settings.BLAZE_TTS_AUDIO_QUALITY
        self.normalization = normalization or settings.BLAZE_TTS_NORMALIZATION
        self.language = language or "vi"

    def validate_configuration(self) -> None:
        """Ensure necessary configuration exists."""
        if not self.api_key or not self.api_key.strip():
            raise BlazeTTSError(
                "BLAZE_API_KEY chưa được cấu hình trong .env. Vui lòng thêm BLAZE_API_KEY để sử dụng tính năng TTS.",
                status_code=401,
            )

    @staticmethod
    def clean_text(text: str) -> str:
        """Clean markdown symbols, bullets, links and code blocks for smooth natural speech."""
        cleaned = re.sub(r"```[\s\S]*?```", "", text)
        cleaned = re.sub(r"`.*?`", "", cleaned)
        cleaned = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", cleaned)
        cleaned = re.sub(r"[*_~#>-]", " ", cleaned)
        cleaned = re.sub(r"https?://\S+", "", cleaned)
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        return cleaned

    @staticmethod
    async def _recv_json(ws: websockets.ClientConnection, timeout: float = 15.0) -> dict:
        """Helper to receive and parse a JSON message frame from Blaze WebSocket."""
        raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
        if isinstance(raw, bytes):
            raise ValueError(f"Expected JSON text message, but received {len(raw)} bytes binary data.")
        return json.loads(raw)

    async def stream_speech(self, text: str) -> AsyncGenerator[bytes, None]:
        """Stream synthesized audio chunks in real-time from Blaze WebSocket API."""
        self.validate_configuration()

        cleaned_text = self.clean_text(text)
        if not cleaned_text:
            raise BlazeTTSError("Nội dung văn bản để đọc không được để trống.", status_code=400)

        cache_key = hashlib.sha256(
            f"{cleaned_text}:{self.speaker_id}:{self.model}:{self.speed}:{self.audio_format}".encode("utf-8")
        ).hexdigest()

        # Check in-memory audio cache
        if cache_key in self._audio_cache:
            logger.info("Serving realtime TTS from memory cache (key=%s)", cache_key[:8])
            cached_audio = self._audio_cache[cache_key]
            chunk_size = 8192
            for i in range(0, len(cached_audio), chunk_size):
                yield cached_audio[i : i + chunk_size]
            return

        query_payload = {
            "query": cleaned_text,
            "language": self.language,
            "audio_format": self.audio_format,
            "audio_quality": self.audio_quality,
            "audio_speed": str(self.speed),
            "speaker_id": self.speaker_id,
            "normalization": self.normalization,
            "model": self.model,
        }

        auth_payload = {
            "token": self.api_key.strip(),
            "strategy": "request",
        }

        collected_chunks: list[bytes] = []

        try:
            async with websockets.connect(self.ws_url, ping_interval=None) as ws:
                # 1. Wait for connection handshake
                conn_msg = await self._recv_json(ws, timeout=10.0)
                if conn_msg.get("type") != "successful-connection":
                    logger.error("Blaze TTS connection handshake failed: %s", conn_msg)
                    raise BlazeTTSError("Không thể kết nối đến máy chủ Blaze TTS Realtime.", status_code=502)

                # 2. Authenticate
                await ws.send(json.dumps(auth_payload))
                auth_msg = await self._recv_json(ws, timeout=10.0)
                if auth_msg.get("type") != "successful-authentication":
                    logger.error("Blaze TTS authentication rejected: %s", auth_msg)
                    raise BlazeTTSError("Blaze API Key không hợp lệ hoặc đã hết hạn.", status_code=401)

                # 3. Send TTS Query
                await ws.send(json.dumps(query_payload))

                # 4. Processing acknowledgment
                proc_msg = await self._recv_json(ws, timeout=15.0)
                if proc_msg.get("type") not in ("processing-request", "started-byte-stream"):
                    logger.warning("Unexpected Blaze response after query: %s", proc_msg)

                # 5. Wait for started-byte-stream event
                if proc_msg.get("status") != "started-byte-stream":
                    start_msg = await self._recv_json(ws, timeout=15.0)
                    if start_msg.get("status") != "started-byte-stream":
                        logger.error("Blaze did not start byte stream: %s", start_msg)
                        raise BlazeTTSError("Máy chủ Blaze TTS không bắt đầu stream âm thanh.", status_code=502)

                # 6. Stream binary chunks in real-time
                while True:
                    frame = await asyncio.wait_for(ws.recv(), timeout=30.0)
                    if isinstance(frame, bytes):
                        collected_chunks.append(frame)
                        yield frame
                        continue

                    data = json.loads(frame)
                    event = data.get("type") or data.get("status")
                    if event == "finished-byte-stream":
                        break
                    if event in ("failed-request", "internal-error"):
                        err_msg = data.get("message", "Lỗi tạo giọng đọc từ máy chủ Blaze AI.")
                        logger.error("Blaze TTS stream error: %s", data)
                        raise BlazeTTSError(err_msg, status_code=502)

        except ConnectionClosed as e:
            logger.error("Blaze TTS WebSocket connection closed unexpectedly: %s", e)
            if not collected_chunks:
                raise BlazeTTSError("Mất kết nối với máy chủ Blaze TTS Realtime.", status_code=502)
        except WebSocketException as e:
            logger.error("Blaze TTS WebSocket error: %s", e)
            if not collected_chunks:
                raise BlazeTTSError(f"Lỗi WebSocket Blaze TTS: {str(e)}", status_code=502)
        except asyncio.TimeoutError:
            logger.error("Blaze TTS WebSocket request timed out.")
            if not collected_chunks:
                raise BlazeTTSError("Quá thời gian chờ phản hồi từ Blaze TTS Realtime.", status_code=504)

        # Cache complete audio if successfully received
        full_audio = b"".join(collected_chunks)
        if full_audio:
            self._audio_cache[cache_key] = full_audio
            logger.info("Blaze TTS audio cached successfully (%d bytes, %d chunks)", len(full_audio), len(collected_chunks))

    async def synthesize_speech(self, text: str) -> bytes:
        """Synthesize text into complete audio bytes (MP3) using Realtime WebSocket stream."""
        chunks: list[bytes] = []
        async for chunk in self.stream_speech(text):
            chunks.append(chunk)

        full_audio = b"".join(chunks)
        if not full_audio:
            raise BlazeTTSError("Không nhận được dữ liệu âm thanh từ Blaze TTS.", status_code=502)
        return full_audio
