import asyncio
import hashlib
import json
import logging
from typing import Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class BlazeTTSError(Exception):
    """Base exception for Blaze TTS operations."""

    def __init__(self, message: str, status_code: int = 500):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class BlazeTTSService:
    """Service to handle Text-to-Speech synthesis with Blaze AI (api.blaze.vn)."""

    _http_client: Optional[httpx.AsyncClient] = None
    _audio_cache: dict[str, bytes] = {}

    def __init__(
        self,
        api_key: Optional[str] = None,
        api_url: Optional[str] = None,
        speaker_id: Optional[str] = None,
        model: Optional[str] = None,
        speed: Optional[str] = None,
        audio_format: Optional[str] = None,
        audio_quality: Optional[int] = None,
        normalization: Optional[str] = None,
        language: Optional[str] = None,
    ):
        self.api_key = api_key if api_key is not None else settings.BLAZE_API_KEY
        self.api_url = api_url or settings.BLAZE_TTS_API_URL
        self.speaker_id = speaker_id or settings.BLAZE_TTS_SPEAKER_ID
        self.model = model or settings.BLAZE_TTS_MODEL
        self.speed = speed or settings.BLAZE_TTS_SPEED
        self.audio_format = audio_format or settings.BLAZE_TTS_AUDIO_FORMAT
        self.audio_quality = audio_quality or settings.BLAZE_TTS_AUDIO_QUALITY
        self.normalization = normalization or settings.BLAZE_TTS_NORMALIZATION
        self.language = language or "vi"

    @classmethod
    def get_http_client(cls) -> httpx.AsyncClient:
        """Get or initialize persistent HTTP client with connection pooling."""
        if cls._http_client is None or cls._http_client.is_closed:
            cls._http_client = httpx.AsyncClient(
                timeout=20.0,
                limits=httpx.Limits(max_keepalive_connections=10, max_connections=20, keepalive_expiry=60.0),
            )
        return cls._http_client

    def validate_configuration(self) -> None:
        """Ensure necessary configuration exists."""
        if not self.api_key or not self.api_key.strip():
            raise BlazeTTSError(
                "BLAZE_API_KEY chưa được cấu hình trong .env. Vui lòng thêm BLAZE_API_KEY để sử dụng tính năng TTS.",
                status_code=401,
            )

    async def create_tts(
        self,
        text: str,
        language: str = "vi",
        speaker_id: str = "HN-Nam-1-BL",
        model: str = "v2.0_pro",
        audio_speed: str = "1",
        audio_quality: int = 64,
        audio_format: str = "wav",
        normalization: str = "basic",
    ) -> dict:
        self.validate_configuration()
        
        import re
        cleaned_text = re.sub(r"```[\s\S]*?```", "", text)
        cleaned_text = re.sub(r"`.*?`", "", cleaned_text)
        cleaned_text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", cleaned_text)
        cleaned_text = re.sub(r"[*_~#>-]", " ", cleaned_text)
        cleaned_text = re.sub(r"https?://\S+", "", cleaned_text)
        cleaned_text = re.sub(r"\s+", " ", cleaned_text).strip()

        if not cleaned_text:
            raise BlazeTTSError("Nội dung văn bản để đọc không được để trống.", status_code=400)

        headers = {
            "Authorization": f"Bearer {self.api_key.strip()}",
            "Content-Type": "application/json",
        }

        payload = {
            "query": cleaned_text,
            "language": language,
            "audio_speed": audio_speed,
            "audio_quality": audio_quality,
            "audio_format": audio_format,
            "normalization": normalization,
            "speaker_id": speaker_id,
            "model": model,
        }

        client = self.get_http_client()
        try:
            res = await client.post(self.api_url, json=payload, headers=headers, timeout=10.0)
        except httpx.TimeoutException:
            raise BlazeTTSError("Kết nối tới Blaze TTS bị quá hạn (Timeout).", status_code=504)
        except Exception as e:
            logger.error("Failed to connect to Blaze TTS: %s", e)
            raise BlazeTTSError(f"Lỗi kết nối tới máy chủ Blaze TTS: {str(e)}", status_code=503)

        if res.status_code in (401, 403):
            raise BlazeTTSError("Blaze API Key không hợp lệ hoặc không có quyền truy cập.", status_code=401)
        if res.status_code == 429:
            raise BlazeTTSError("Quá số lượng yêu cầu cho phép (Rate limit).", status_code=429)
        if res.status_code not in (200, 202):
            logger.error("Blaze TTS creation failed with HTTP %s: %s", res.status_code, res.text)
            raise BlazeTTSError(f"Dịch vụ Blaze TTS trả về mã lỗi HTTP {res.status_code}.", status_code=502)

        data = res.json()
        return data

    async def get_tts_info(self, tts_id: str) -> dict:
        self.validate_configuration()
        headers = {
            "Authorization": f"Bearer {self.api_key.strip()}",
        }
        url = f"{self.api_url.rstrip('/')}/{tts_id}/info"
        client = self.get_http_client()
        try:
            res = await client.get(url, headers=headers, timeout=10.0)
        except httpx.TimeoutException:
            raise BlazeTTSError("Kết nối tới Blaze TTS bị quá hạn (Timeout).", status_code=504)
        except Exception as e:
            raise BlazeTTSError(f"Lỗi kết nối tới máy chủ Blaze TTS: {str(e)}", status_code=503)

        if res.status_code == 404:
            raise BlazeTTSError("Không tìm thấy TTS ID này.", status_code=404)
        if res.status_code in (401, 403):
            raise BlazeTTSError("Blaze API Key không hợp lệ.", status_code=401)
        if res.status_code != 200:
            raise BlazeTTSError(f"Lỗi từ dịch vụ Blaze TTS (HTTP {res.status_code}).", status_code=502)
        
        return res.json()

    async def get_tts_options(self) -> dict:
        self.validate_configuration()
        headers = {
            "Authorization": f"Bearer {self.api_key.strip()}",
        }
        url = f"{self.api_url.rstrip('/')}/options"
        # Blaze might not have this exact url, using base url as defined, but appending /options
        # since settings.BLAZE_TTS_API_URL is "https://api.blaze.vn/v1/tts", we replace "tts" with "tts/options" or just append to base
        # But wait, api_url is typically "https://api.blaze.vn/v1/tts".
        # If url is "https://api.blaze.vn/v1/tts/options", it matches requirements.
        client = self.get_http_client()
        try:
            res = await client.get(url, headers=headers, timeout=10.0)
        except httpx.TimeoutException:
            raise BlazeTTSError("Kết nối tới Blaze TTS bị quá hạn (Timeout).", status_code=504)
        except Exception as e:
            raise BlazeTTSError(f"Lỗi kết nối tới máy chủ Blaze TTS: {str(e)}", status_code=503)

        if res.status_code in (401, 403):
            raise BlazeTTSError("Blaze API Key không hợp lệ.", status_code=401)
        if res.status_code != 200:
            raise BlazeTTSError(f"Lỗi từ dịch vụ Blaze TTS (HTTP {res.status_code}).", status_code=502)
        
        return res.json()

    async def stream_audio(self, tts_id: str):
        self.validate_configuration()
        headers = {
            "Authorization": f"Bearer {self.api_key.strip()}",
        }
        url = f"{self.api_url.rstrip('/')}/{tts_id}/play"
        
        async with httpx.AsyncClient() as client:
            try:
                async with client.stream("GET", url, headers=headers, timeout=30.0) as res:
                    if res.status_code == 404:
                        yield b"Not Found"
                        return
                    if res.status_code in (401, 403):
                        yield b"Unauthorized"
                        return
                    if res.status_code != 200:
                        yield b"Error"
                        return
                    async for chunk in res.aiter_bytes():
                        yield chunk
            except Exception as e:
                logger.error("Error streaming audio: %s", e)
                yield b"Stream Error"
        if not self.api_key or not self.api_key.strip():
            raise BlazeTTSError(
                "BLAZE_API_KEY chưa được cấu hình trong .env. Vui lòng thêm BLAZE_API_KEY để sử dụng tính năng TTS.",
                status_code=401,
            )

    async def synthesize_speech(self, text: str) -> bytes:
        """Synthesize text into WAV audio bytes using Blaze AI TTS."""
        self.validate_configuration()

        import re
        # Clean markdown symbols, bullets, links and code blocks for smooth TTS
        cleaned_text = re.sub(r"```[\s\S]*?```", "", text)
        cleaned_text = re.sub(r"`.*?`", "", cleaned_text)
        cleaned_text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", cleaned_text)
        cleaned_text = re.sub(r"[*_~#>-]", " ", cleaned_text)
        cleaned_text = re.sub(r"https?://\S+", "", cleaned_text)
        cleaned_text = re.sub(r"\s+", " ", cleaned_text).strip()

        if not cleaned_text:
            raise BlazeTTSError("Nội dung văn bản để đọc không được để trống.", status_code=400)

        # Check in-memory audio cache
        cache_key = hashlib.sha256(
            f"{cleaned_text}:{self.speaker_id}:{self.model}:{self.speed}".encode("utf-8")
        ).hexdigest()

        if cache_key in self._audio_cache:
            logger.info("Serving synthesized speech from cache (key=%s)", cache_key[:8])
            return self._audio_cache[cache_key]

        headers = {
            "Authorization": f"Bearer {self.api_key.strip()}",
            "Content-Type": "application/json",
        }

        payload = {
            "query": cleaned_text,
            "language": self.language,
            "audio_speed": self.speed,
            "audio_quality": self.audio_quality,
            "audio_format": self.audio_format,
            "normalization": self.normalization,
            "speaker_id": self.speaker_id,
            "model": self.model,
        }

        client = self.get_http_client()

        # 1. Submit TTS generation request
        try:
            res = await client.post(self.api_url, json=payload, headers=headers)
        except Exception as e:
            logger.error("Failed to connect to Blaze TTS: %s", e)
            raise BlazeTTSError(f"Lỗi kết nối tới máy chủ Blaze TTS: {str(e)}", status_code=503)

        if res.status_code in (401, 403):
            raise BlazeTTSError("Blaze API Key không hợp lệ hoặc không có quyền truy cập.", status_code=401)

        if res.status_code not in (200, 202):
            logger.error("Blaze TTS creation failed with HTTP %s: %s", res.status_code, res.text)
            raise BlazeTTSError(f"Dịch vụ Blaze TTS trả về mã lỗi HTTP {res.status_code}.", status_code=502)

        data = res.json()
        tts_id = data.get("id")
        if not tts_id:
            raise BlazeTTSError("Blaze TTS không trả về định danh âm thanh hợp lệ.", status_code=502)

        # 2. Fast adaptive polling for audio completion at /v1/tts/{tts_id}/play
        play_url = f"{self.api_url.rstrip('/')}/{tts_id}/play"
        max_attempts = 50
        poll_interval = 0.12

        for attempt in range(max_attempts):
            await asyncio.sleep(poll_interval)
            try:
                play_res = await client.get(play_url, headers=headers)
                if play_res.status_code == 200 and len(play_res.content) > 500:
                    audio_bytes = play_res.content
                    self._audio_cache[cache_key] = audio_bytes
                    logger.info("Blaze TTS speech generated successfully in %.2fs (%d bytes)", (attempt + 1) * poll_interval, len(audio_bytes))
                    return audio_bytes

                if play_res.status_code in (401, 403):
                    raise BlazeTTSError("Blaze API Key không hợp lệ trong quá trình lấy audio.", status_code=401)

                if play_res.status_code not in (200, 425):
                    logger.warning("Blaze TTS play endpoint returned HTTP %s on attempt %d", play_res.status_code, attempt + 1)

            except BlazeTTSError:
                raise
            except Exception as e:
                logger.debug("TTS polling attempt %d error: %s", attempt + 1, e)

        raise BlazeTTSError("Quá thời gian chờ tạo âm thanh từ dịch vụ Blaze TTS.", status_code=504)
