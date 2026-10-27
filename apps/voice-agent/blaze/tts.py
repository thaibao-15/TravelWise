"""Blaze AI Text-To-Speech (TTS) Adapter for LiveKit Agents."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Optional

import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatusCode

from livekit.agents import (
    DEFAULT_API_CONNECT_OPTIONS,
    APIConnectOptions,
    tts,
    utils,
)

from config import config
from .exceptions import (
    BlazeAuthError,
    BlazeConnectionError,
    BlazeTTSError,
    BlazeTimeoutError,
)

logger = logging.getLogger("travelwise.blaze.tts")


class BlazeTTS(tts.TTS):
    """Blaze AI Realtime TTS provider plugin for LiveKit Agents.

    Connects to Blaze AI's WebSocket TTS service (wss://api.blaze.vn/v1/tts/realtime)
    with pipelined query synthesis, MP3 streaming, and native livekit AudioStreamDecoder.
    """

    def __init__(
        self,
        *,
        api_key: Optional[str] = None,
        ws_url: Optional[str] = None,
        speaker_id: Optional[str] = None,
        model: Optional[str] = None,
        speed: Optional[str] = None,
        audio_quality: Optional[int] = None,
        audio_format: Optional[str] = None,
        normalization: Optional[str] = None,
        sample_rate: int = 24000,
        num_channels: int = 1,
    ) -> None:
        super().__init__(
            capabilities=tts.TTSCapabilities(
                streaming=False,
                aligned_transcript=False,
            ),
            sample_rate=sample_rate,
            num_channels=num_channels,
        )
        self._api_key = api_key.strip() if api_key is not None else config.BLAZE_API_KEY.strip()
        self._ws_url = ws_url.strip() if ws_url is not None else config.BLAZE_TTS_WS_URL.strip()
        self._speaker_id = speaker_id.strip() if speaker_id is not None else config.BLAZE_TTS_SPEAKER_ID.strip()
        self._model = model.strip() if model is not None else config.BLAZE_TTS_MODEL.strip()
        self._speed = speed.strip() if speed is not None else config.BLAZE_TTS_SPEED.strip()
        self._audio_quality = audio_quality if audio_quality is not None else config.BLAZE_TTS_AUDIO_QUALITY
        self._audio_format = audio_format.strip() if audio_format is not None else config.BLAZE_TTS_AUDIO_FORMAT.strip()
        self._normalization = normalization.strip() if normalization is not None else config.BLAZE_TTS_NORMALIZATION.strip()

    @property
    def model(self) -> str:
        return self._model

    @property
    def provider(self) -> str:
        return "blaze"

    @property
    def speaker_id(self) -> str:
        return self._speaker_id

    @property
    def speed(self) -> str:
        return self._speed

    @property
    def audio_quality(self) -> int:
        return self._audio_quality

    @property
    def audio_format(self) -> str:
        return self._audio_format

    @property
    def normalization(self) -> str:
        return self._normalization

    @property
    def api_key(self) -> str:
        return self._api_key

    @property
    def ws_url(self) -> str:
        return self._ws_url

    def synthesize(
        self,
        text: str,
        *,
        conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS,
    ) -> BlazeChunkedStream:
        """Synthesize text into speech using Blaze AI Realtime WebSocket API."""
        return BlazeChunkedStream(
            tts=self,
            input_text=text,
            conn_options=conn_options,
        )


class BlazeChunkedStream(tts.ChunkedStream):
    """Audio stream executing real-time speech synthesis against Blaze TTS."""

    def __init__(
        self,
        *,
        tts: BlazeTTS,
        input_text: str,
        conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS,
    ) -> None:
        super().__init__(
            tts=tts,
            input_text=input_text,
            conn_options=conn_options,
        )
        self._tts: BlazeTTS = tts

    async def _run(self, output_emitter: tts.AudioEmitter) -> None:
        """Execute WebSocket session, stream MP3 chunks, and decode into PCM frames."""
        clean_text = self._input_text.strip()
        if not clean_text:
            return

        if not self._tts.api_key:
            raise BlazeAuthError("BLAZE_API_KEY chưa được cấu hình cho Blaze AI TTS.")

        req_id = utils.shortuuid()
        output_emitter.initialize(
            request_id=req_id,
            sample_rate=self._tts.sample_rate,
            num_channels=self._tts.num_channels,
            mime_type=f"audio/{self._tts.audio_format}",
            stream=False,
        )

        ws_url = self._tts.ws_url or "wss://api.blaze.vn/v1/tts/realtime"
        connect_timeout = self._conn_options.timeout or 10.0

        try:
            logger.debug(
                "Connecting to Blaze TTS WebSocket: %s (speaker=%s, model=%s)",
                ws_url,
                self._tts.speaker_id,
                self._tts.model,
            )

            async with websockets.connect(
                ws_url,
                open_timeout=connect_timeout,
                max_size=10 * 1024 * 1024,
                ping_interval=None,
            ) as ws:
                # 1. Pipelined Authentication Frame
                auth_msg = {
                    "token": self._tts.api_key,
                    "strategy": "request",
                }
                await ws.send(json.dumps(auth_msg))

                # 2. Pipelined Query Frame
                query_msg = {
                    "query": clean_text,
                    "language": "vi",
                    "audio_format": self._tts.audio_format,
                    "audio_quality": self._tts.audio_quality,
                    "audio_speed": str(self._tts.speed),
                    "speaker_id": self._tts.speaker_id,
                    "normalization": self._tts.normalization,
                    "model": self._tts.model,
                }
                await ws.send(json.dumps(query_msg))

                # 3. Receive binary audio stream
                bytes_received = 0
                while True:
                    try:
                        raw_msg = await asyncio.wait_for(ws.recv(), timeout=connect_timeout)
                    except asyncio.TimeoutError as exc:
                        raise BlazeTimeoutError("Quá thời gian chờ phản hồi âm thanh từ Blaze TTS.") from exc

                    if isinstance(raw_msg, bytes):
                        bytes_received += len(raw_msg)
                        output_emitter.push(raw_msg)
                    elif isinstance(raw_msg, str):
                        try:
                            data = json.loads(raw_msg)
                        except Exception:
                            continue

                        event = data.get("type") or data.get("status")
                        if event == "finished-byte-stream":
                            logger.debug("Blaze TTS stream hoàn tất. Tổng dung lượng nhận: %d bytes", bytes_received)
                            break
                        elif event in ("failed-request", "internal-error", "error"):
                            err_msg = data.get("message") or "Lỗi từ dịch vụ tạo giọng đọc Blaze AI TTS."
                            raise BlazeTTSError(err_msg)

        except InvalidStatusCode as exc:
            status = getattr(exc.response, "status_code", -1)
            if status in (401, 403):
                raise BlazeAuthError(f"Blaze API Key không hợp lệ hoặc bị từ chối (HTTP {status}).") from exc
            raise BlazeConnectionError(f"Máy chủ Blaze TTS trả về mã lỗi HTTP {status}.") from exc
        except ConnectionClosed as exc:
            if exc.code in (1000, 1001):
                logger.debug("Blaze TTS WebSocket đóng bình thường: %s", exc)
                return
            raise BlazeConnectionError(f"Mất kết nối với Blaze TTS (code: {exc.code}, reason: {exc.reason})") from exc
        except (BlazeAuthError, BlazeConnectionError, BlazeTimeoutError, BlazeTTSError):
            raise
        except asyncio.CancelledError:
            logger.debug("Blaze TTS synthesize cancelled.")
            raise
        except Exception as exc:
            logger.error("Lỗi không xác định trong Blaze TTS stream: %s", exc, exc_info=True)
            raise BlazeTTSError(f"Lỗi phiên TTS Blaze AI: {str(exc)}") from exc
