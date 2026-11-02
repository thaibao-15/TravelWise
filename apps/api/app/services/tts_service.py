import asyncio
import hashlib
import json
import logging
import re
from typing import Any, AsyncGenerator, Optional, Union
from urllib.parse import urlencode

import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatus, WebSocketException

from app.core.config import settings

logger = logging.getLogger(__name__)


class BlazeTTSError(Exception):
    """Base exception for Blaze TTS operations."""

    def __init__(
        self,
        message: str,
        status_code: int = 500,
        error_type: Optional[str] = None,
        code: Optional[str] = None,
    ):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.error_type = error_type
        self.code = code

    def to_dict(self) -> dict:
        return {
            "type": "error",
            "error": {
                "message": self.message,
                "type": self.error_type or "tts_error",
                "code": self.code,
            },
        }


class RealtimeTTSStreamSession:
    """Active WebSocket session with Blaze TTS Realtime for low-latency voice synthesis and token streaming."""

    def __init__(self, ws: Any, session_config: dict):
        self.ws = ws
        self.session_config = session_config
        self.is_closed = False

    async def update_session(self, **kwargs) -> dict:
        """Send session.update event to reconfigure current session settings."""
        valid_keys = {"model", "voice", "language", "response_format", "sample_rate", "speed"}
        filtered = {k: v for k, v in kwargs.items() if k in valid_keys and v is not None}
        if "speed" in filtered and filtered["speed"] is not None:
            filtered["speed"] = float(filtered["speed"])
        if "sample_rate" in filtered and filtered["sample_rate"] is not None:
            filtered["sample_rate"] = int(filtered["sample_rate"])

        await self.ws.send(json.dumps({"type": "session.update", "session": filtered}))
        while True:
            msg = await self.ws.recv()
            if isinstance(msg, bytes):
                continue
            data = json.loads(msg)
            event_type = data.get("type")
            if event_type == "session.updated":
                self.session_config.update(data.get("session", {}))
                return self.session_config
            if event_type == "error":
                raise BlazeTTSService.error_from_event(data)

    async def append_token(self, text: str) -> None:
        """Send input_text.append to buffer LLM token into Blaze TTS (mode=stream)."""
        await self.ws.send(json.dumps({"type": "input_text.append", "text": text}))

    async def flush(self) -> None:
        """Send input_text.flush to trigger reading buffered tokens (mode=stream)."""
        await self.ws.send(json.dumps({"type": "input_text.flush"}))

    async def create_speech(self, text: str, **overrides) -> None:
        """Send speech.create event to synthesize a single sentence (mode=request)."""
        payload: dict[str, Any] = {"type": "speech.create", "input": text}
        for k, v in overrides.items():
            if v is not None:
                payload[k] = v
        await self.ws.send(json.dumps(payload))

    async def receive_speech_audio(self, timeout: float = 25.0) -> AsyncGenerator[bytes, None]:
        """Yield binary audio chunks until speech.done event is received."""
        while True:
            frame = await asyncio.wait_for(self.ws.recv(), timeout=timeout)
            if isinstance(frame, bytes):
                yield frame
                continue

            data = json.loads(frame)
            event_type = data.get("type")
            if event_type == "speech.done":
                break
            if event_type == "error":
                raise BlazeTTSService.error_from_event(data)

    async def close(self) -> None:
        """Close session gracefully by sending session.close."""
        if not self.is_closed:
            self.is_closed = True
            try:
                await self.ws.send(json.dumps({"type": "session.close"}))
                try:
                    msg = await asyncio.wait_for(self.ws.recv(), timeout=2.0)
                    if isinstance(msg, str):
                        data = json.loads(msg)
                        if data.get("type") == "session.closed":
                            pass
                except Exception:
                    pass
                await self.ws.close()
            except Exception:
                pass


class BlazeTTSService:
    """Service to handle Realtime Text-to-Speech synthesis with Blaze AI via WebSocket."""

    _audio_cache: dict[str, bytes] = {}
    _inflight_futures: dict[str, asyncio.Future] = {}

    def __init__(
        self,
        api_key: Optional[str] = None,
        ws_url: Optional[str] = None,
        speaker_id: Optional[str] = None,
        voice: Optional[str] = None,
        model: Optional[str] = None,
        speed: Optional[Union[str, float]] = None,
        audio_format: Optional[str] = None,
        response_format: Optional[str] = None,
        language: Optional[str] = None,
        sample_rate: Optional[int] = None,
        mode: Optional[str] = None,
    ):
        self.api_key = api_key if api_key is not None else settings.BLAZE_API_KEY
        self.ws_url = ws_url or settings.BLAZE_TTS_WS_URL
        self.speaker_id = voice or speaker_id or settings.BLAZE_TTS_SPEAKER_ID
        self.model = model or settings.BLAZE_TTS_MODEL
        self.speed = speed if speed is not None else settings.BLAZE_TTS_SPEED
        self.audio_format = response_format or audio_format or settings.BLAZE_TTS_AUDIO_FORMAT
        self.language = language or getattr(settings, "BLAZE_TTS_LANGUAGE", "vi")
        self.sample_rate = sample_rate or settings.BLAZE_TTS_SAMPLE_RATE
        self.mode = mode

    def connection_url(self, overrides: Optional[dict] = None) -> str:
        """Build WebSocket connection URL with default session parameters."""
        raw_speed = overrides.get("speed") if overrides and "speed" in overrides else self.speed
        speed_float = float(raw_speed) if raw_speed is not None else 1.0

        raw_sample_rate = overrides.get("sample_rate") if overrides and "sample_rate" in overrides else self.sample_rate
        sample_rate_int = int(raw_sample_rate) if raw_sample_rate is not None else 24000

        params_dict: dict[str, Any] = {
            "model": (overrides.get("model") if overrides else None) or self.model,
            "voice": (overrides.get("voice") or overrides.get("speaker_id") if overrides else None) or self.speaker_id,
            "language": (overrides.get("language") if overrides else None) or self.language,
            "response_format": (overrides.get("response_format") or overrides.get("audio_format") if overrides else None) or self.audio_format,
            "sample_rate": sample_rate_int,
            "speed": speed_float,
        }
        mode = (overrides.get("mode") if overrides else None) or self.mode
        if mode:
            params_dict["mode"] = mode

        # Filter out None values
        filtered = {k: v for k, v in params_dict.items() if v is not None}
        params = urlencode(filtered)
        separator = "&" if "?" in self.ws_url else "?"
        return f"{self.ws_url}{separator}{params}"

    def _connection_url(self, overrides: Optional[dict] = None) -> str:
        """Backward-compatible alias for connection_url."""
        return self.connection_url(overrides=overrides)

    def validate_configuration(self) -> None:
        """Ensure necessary configuration exists."""
        if not self.api_key or not self.api_key.strip():
            raise BlazeTTSError(
                "BLAZE_API_KEY chưa được cấu hình trong .env. Vui lòng thêm BLAZE_API_KEY để sử dụng tính năng TTS.",
                status_code=401,
                error_type="unauthorized",
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
    def error_from_event(data: dict) -> BlazeTTSError:
        """Parse error event according to protocol: {'type': 'error', 'error': {'message', 'type', 'code'}}."""
        error = data.get("error")
        if isinstance(error, dict):
            message = error.get("message")
            err_type = error.get("type")
            code = error.get("code")

            if err_type == "insufficient_credits_error":
                return BlazeTTSError(
                    message or "Tài khoản Blaze AI không đủ credits (Insufficient credits).",
                    status_code=402,
                    error_type=err_type,
                    code=code,
                )
            if err_type in ("invalid_request_error", "validation_error"):
                return BlazeTTSError(
                    message or "Yêu cầu tổng hợp giọng nói không hợp lệ.",
                    status_code=400,
                    error_type=err_type,
                    code=code,
                )
            if err_type in ("authentication_error", "unauthorized"):
                return BlazeTTSError(
                    message or "Blaze API Key không hợp lệ hoặc hết hạn.",
                    status_code=401,
                    error_type=err_type,
                    code=code,
                )
            if err_type == "rate_limit_error":
                return BlazeTTSError(
                    message or "Quá giới hạn tần suất yêu cầu TTS (Rate limit exceeded).",
                    status_code=429,
                    error_type=err_type,
                    code=code,
                )
            return BlazeTTSError(
                message or "Lỗi từ máy chủ Blaze TTS.",
                status_code=502,
                error_type=err_type,
                code=code,
            )

        msg = data.get("message") or "Lỗi không xác định từ máy chủ Blaze TTS."
        return BlazeTTSError(msg, status_code=502)

    @classmethod
    def _error_from_event(cls, data: dict) -> BlazeTTSError:
        """Backward-compatible alias for error_from_event."""
        return cls.error_from_event(data)

    async def connect_session(self, overrides: Optional[dict] = None) -> RealtimeTTSStreamSession:
        """Open a WebSocket session to Blaze TTS Realtime and wait for session.created."""
        self.validate_configuration()
        url = self.connection_url(overrides=overrides)
        headers = {"Authorization": f"Bearer {self.api_key.strip()}"}

        try:
            ws = await websockets.connect(url, additional_headers=headers, ping_interval=None)
            first_msg = await asyncio.wait_for(ws.recv(), timeout=20.0)
            if isinstance(first_msg, bytes):
                raise BlazeTTSError("Nhận được dữ liệu nhị phân không mong muốn trước khi khởi tạo phiên.", status_code=502)

            data = json.loads(first_msg)
            if data.get("type") == "error":
                raise self.error_from_event(data)
            if data.get("type") != "session.created":
                raise BlazeTTSError(f"Phản hồi không mong muốn từ Blaze TTS: {data.get('type')}", status_code=502)

            return RealtimeTTSStreamSession(ws=ws, session_config=data.get("session", {}))
        except InvalidStatus as e:
            code = getattr(e.response, "status_code", 502)
            if code in (401, 403):
                raise BlazeTTSError("Blaze API Key không hợp lệ hoặc không có quyền truy cập.", status_code=401)
            if code == 429:
                raise BlazeTTSError("Quá giới hạn tần suất yêu cầu TTS (HTTP 429).", status_code=429)
            raise BlazeTTSError(f"Không thể kết nối Blaze TTS Realtime (HTTP {code}).", status_code=502)
        except ConnectionClosed as e:
            raise BlazeTTSError(f"Mất kết nối với máy chủ Blaze TTS Realtime: {e}", status_code=502)
        except WebSocketException as e:
            raise BlazeTTSError(f"Lỗi WebSocket Blaze TTS: {e}", status_code=502)
        except asyncio.TimeoutError:
            raise BlazeTTSError("Quá thời gian chờ phản hồi khởi tạo phiên từ Blaze TTS Realtime.", status_code=504)

    async def stream_speech(
        self,
        text: str,
        overrides: Optional[dict] = None,
    ) -> AsyncGenerator[bytes, None]:
        """Stream synthesized audio chunks in real-time from Blaze WebSocket API with caching & coalescing."""
        self.validate_configuration()

        cleaned_text = self.clean_text(text)
        if not cleaned_text:
            raise BlazeTTSError("Nội dung văn bản để đọc không được để trống.", status_code=400)

        effective_voice = (overrides.get("voice") or overrides.get("speaker_id") if overrides else None) or self.speaker_id
        effective_model = (overrides.get("model") if overrides else None) or self.model
        effective_speed = (overrides.get("speed") if overrides else None) or self.speed
        effective_format = (overrides.get("response_format") or overrides.get("audio_format") if overrides else None) or self.audio_format
        effective_rate = (overrides.get("sample_rate") if overrides else None) or self.sample_rate

        cache_key = hashlib.sha256(
            f"{cleaned_text}:{effective_voice}:{effective_model}:{effective_speed}:{effective_format}:{effective_rate}".encode("utf-8")
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
                pass

        loop = asyncio.get_running_loop()
        future: asyncio.Future = loop.create_future()
        self._inflight_futures[cache_key] = future

        collected_chunks: list[bytes] = []

        try:
            session = await self.connect_session(overrides=overrides)
            try:
                await session.create_speech(cleaned_text)
                async for chunk in session.receive_speech_audio():
                    collected_chunks.append(chunk)
                    yield chunk
            finally:
                await session.close()

            full_audio = b"".join(collected_chunks)
            if full_audio:
                if len(self._audio_cache) > 200:
                    self._audio_cache.pop(next(iter(self._audio_cache)))
                self._audio_cache[cache_key] = full_audio
                if not future.done():
                    future.set_result(full_audio)

        except BlazeTTSError as e:
            if not future.done():
                future.set_exception(e)
                try:
                    future.exception()
                except Exception:
                    pass
            raise
        except Exception as e:
            logger.error("Unexpected error streaming Blaze TTS: %s", e)
            err = BlazeTTSError(f"Lỗi stream âm thanh từ Blaze TTS: {e}", status_code=502)
            if not future.done():
                future.set_exception(err)
                try:
                    future.exception()
                except Exception:
                    pass
            raise err
        finally:
            self._inflight_futures.pop(cache_key, None)

    async def synthesize_speech(self, text: str, overrides: Optional[dict] = None) -> bytes:
        """Synthesize text into complete audio bytes (MP3) using Realtime WebSocket stream."""
        chunks: list[bytes] = []
        async for chunk in self.stream_speech(text, overrides=overrides):
            chunks.append(chunk)

        full_audio = b"".join(chunks)
        if not full_audio:
            raise BlazeTTSError("Không nhận được dữ liệu âm thanh từ Blaze TTS.", status_code=502)
        return full_audio
