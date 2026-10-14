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
    _inflight_futures: dict[str, asyncio.Future] = {}

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

    async def stream_speech(self, text: str) -> AsyncGenerator[bytes, None]:
        """Stream synthesized audio chunks in real-time from Blaze WebSocket API with full pipelining."""
        self.validate_configuration()

        cleaned_text = self.clean_text(text)
        if not cleaned_text:
            raise BlazeTTSError("Nội dung văn bản để đọc không được để trống.", status_code=400)

        cache_key = hashlib.sha256(
            f"{cleaned_text}:{self.speaker_id}:{self.model}:{self.speed}:{self.audio_format}".encode("utf-8")
        ).hexdigest()

        # 1. Fast in-memory cache hit (0ms)
        if cache_key in self._audio_cache:
            cached_audio = self._audio_cache[cache_key]
            chunk_size = 16384
            for i in range(0, len(cached_audio), chunk_size):
                yield cached_audio[i : i + chunk_size]
            return

        # 2. In-flight coalescing: If another request for the same text is in progress, wait for it
        if cache_key in self._inflight_futures:
            logger.info("Coalescing concurrent TTS request for key %s", cache_key[:8])
            try:
                full_audio = await asyncio.shield(self._inflight_futures[cache_key])
                chunk_size = 16384
                for i in range(0, len(full_audio), chunk_size):
                    yield full_audio[i : i + chunk_size]
                return
            except Exception:
                # If the in-flight one failed, continue to do our own fetch
                pass

        loop = asyncio.get_running_loop()
        future: asyncio.Future = loop.create_future()
        self._inflight_futures[cache_key] = future

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
                # Send auth and query immediately in parallel (zero-roundtrip pipelining)
                await ws.send(json.dumps(auth_payload))
                await ws.send(json.dumps(query_payload))

                while True:
                    frame = await asyncio.wait_for(ws.recv(), timeout=20.0)
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

            full_audio = b"".join(collected_chunks)
            if full_audio:
                # Limit cache size to 200 items
                if len(self._audio_cache) > 200:
                    self._audio_cache.pop(next(iter(self._audio_cache)))
                self._audio_cache[cache_key] = full_audio
                if not future.done():
                    future.set_result(full_audio)

        except ConnectionClosed as e:
            logger.error("Blaze TTS WebSocket connection closed: %s", e)
            if not collected_chunks:
                if not future.done():
                    future.set_exception(e)
                raise BlazeTTSError("Mất kết nối với máy chủ Blaze TTS Realtime.", status_code=502)
        except WebSocketException as e:
            logger.error("Blaze TTS WebSocket error: %s", e)
            if not collected_chunks:
                if not future.done():
                    future.set_exception(e)
                raise BlazeTTSError(f"Lỗi WebSocket Blaze TTS: {str(e)}", status_code=502)
        except asyncio.TimeoutError as e:
            logger.error("Blaze TTS WebSocket timed out.")
            if not collected_chunks:
                if not future.done():
                    future.set_exception(e)
                raise BlazeTTSError("Quá thời gian chờ phản hồi từ Blaze TTS Realtime.", status_code=504)
        finally:
            self._inflight_futures.pop(cache_key, None)

    async def synthesize_speech(self, text: str) -> bytes:
        """Synthesize text into complete audio bytes (MP3) using Realtime WebSocket stream."""
        chunks: list[bytes] = []
        async for chunk in self.stream_speech(text):
            chunks.append(chunk)

        full_audio = b"".join(chunks)
        if not full_audio:
            raise BlazeTTSError("Không nhận được dữ liệu âm thanh từ Blaze TTS.", status_code=502)
        return full_audio
