"""Blaze AI Speech-To-Text (STT) Adapter for LiveKit Agents."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Optional

import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatusCode

from livekit import rtc
from livekit.agents import (
    DEFAULT_API_CONNECT_OPTIONS,
    APIConnectOptions,
    stt,
    utils,
)

from config import config
from .exceptions import (
    BlazeAuthError,
    BlazeConnectionError,
    BlazeSTTError,
    BlazeTimeoutError,
)

logger = logging.getLogger("travelwise.blaze.stt")


class BlazeSTT(stt.STT):
    """Blaze AI Realtime STT provider plugin for LiveKit Agents.

    Connects to Blaze AI's WebSocket STT service (wss://api.blaze.vn/v1/stt/realtime)
    to perform real-time speech-to-text with interim and final transcription streaming.
    """

    def __init__(
        self,
        *,
        api_key: Optional[str] = None,
        ws_url: Optional[str] = None,
        model: Optional[str] = None,
        language: Optional[str] = None,
        sample_rate: int = 16000,
    ) -> None:
        super().__init__(
            capabilities=stt.STTCapabilities(
                streaming=True,
                interim_results=True,
            )
        )
        self._api_key = api_key.strip() if api_key is not None else config.BLAZE_API_KEY.strip()
        self._ws_url = ws_url.strip() if ws_url is not None else config.BLAZE_STT_WS_URL.strip()
        self._model = model.strip() if model is not None else config.BLAZE_STT_MODEL.strip()
        self._language = language.strip() if language is not None else config.BLAZE_STT_LANGUAGE.strip()
        self._sample_rate = sample_rate

    @property
    def model(self) -> str:
        return self._model

    @property
    def provider(self) -> str:
        return "blaze"

    @property
    def language(self) -> str:
        return self._language

    @property
    def sample_rate(self) -> int:
        return self._sample_rate

    @property
    def api_key(self) -> str:
        return self._api_key

    @property
    def ws_url(self) -> str:
        return self._ws_url

    async def _recognize_impl(
        self,
        buffer: utils.AudioBuffer,
        *,
        language: Optional[str] = None,
        conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS,
    ) -> stt.SpeechEvent:
        """Recognize non-streaming audio buffer by feeding it through the stream adapter."""
        target_lang = language or self._language
        stream = self.stream(language=target_lang, conn_options=conn_options)

        for frame in buffer:
            stream.push_frame(frame)
        stream.end_input()

        final_event: Optional[stt.SpeechEvent] = None
        async for ev in stream:
            if ev.type == stt.SpeechEventType.FINAL_TRANSCRIPT:
                final_event = ev

        if final_event is not None:
            return final_event

        return stt.SpeechEvent(
            type=stt.SpeechEventType.FINAL_TRANSCRIPT,
            alternatives=[stt.SpeechData(language=target_lang, text="")],
        )

    def stream(
        self,
        *,
        language: Optional[str] = None,
        conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS,
    ) -> BlazeSpeechStream:
        """Create a real-time speech recognition stream for LiveKit audio frames."""
        return BlazeSpeechStream(
            stt=self,
            language=language or self._language,
            conn_options=conn_options,
        )


class BlazeSpeechStream(stt.SpeechStream):
    """Streaming audio session connected to Blaze AI STT WebSocket."""

    def __init__(
        self,
        *,
        stt: BlazeSTT,
        language: str,
        conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS,
    ) -> None:
        super().__init__(
            stt=stt,
            conn_options=conn_options,
            sample_rate=stt.sample_rate,  # Automatically resamples LiveKit frames to 16kHz
        )
        self._stt: BlazeSTT = stt
        self._language = language
        self._ws: Optional[websockets.ClientConnection] = None

    async def _run(self) -> None:
        """Run the streaming STT worker loop with bidirectional WebSocket streaming."""
        if not self._stt.api_key:
            raise BlazeAuthError("BLAZE_API_KEY chưa được cấu hình cho Blaze AI STT.")

        ws_url = self._stt.ws_url or "wss://api.blaze.vn/v1/stt/realtime"
        connect_timeout = self._conn_options.timeout or 10.0

        try:
            logger.debug("Connecting to Blaze STT WebSocket: %s (model=%s, lang=%s)", ws_url, self._stt.model, self._language)
            async with websockets.connect(
                ws_url,
                open_timeout=connect_timeout,
                max_size=10 * 1024 * 1024,
                ping_interval=20,
                ping_timeout=20,
            ) as ws:
                self._ws = ws
                self._report_connection_acquired(acquire_time=0.0, connection_reused=False)

                # 1. Send authentication handshake frame
                auth_payload = {
                    "token": self._stt.api_key,
                    "language": self._language,
                    "model": self._stt.model,
                }
                await ws.send(json.dumps(auth_payload))

                # 2. Wait for server confirmation (ready)
                ready = False
                while not ready:
                    try:
                        msg_raw = await asyncio.wait_for(ws.recv(), timeout=connect_timeout)
                    except asyncio.TimeoutError as exc:
                        raise BlazeTimeoutError("Quá thời gian chờ handshake sẵn sàng từ Blaze STT.") from exc

                    if isinstance(msg_raw, str):
                        data = json.loads(msg_raw)
                        msg_type = data.get("type")
                        if msg_type == "ready":
                            ready = True
                        elif msg_type == "error":
                            err_msg = data.get("message") or "Lỗi xác thực từ máy chủ Blaze STT."
                            raise BlazeAuthError(err_msg)
                        elif msg_type == "successful-authentication":
                            continue

                logger.debug("Blaze AI STT handshake thành công. Bắt đầu truyền luồng âm thanh.")

                # 3. Bidirectional streaming: sender task + receiver task
                send_task = asyncio.create_task(self._send_loop(ws), name="BlazeSTT._send_loop")
                recv_task = asyncio.create_task(self._recv_loop(ws), name="BlazeSTT._recv_loop")

                tasks = [send_task, recv_task]
                done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_EXCEPTION)

                if pending:
                    for t in pending:
                        t.cancel()
                    await asyncio.gather(*pending, return_exceptions=True)

                for t in done:
                    if not t.cancelled():
                        exc = t.exception()
                        if exc is not None:
                            raise exc

        except InvalidStatusCode as exc:
            status = getattr(exc.response, "status_code", -1)
            if status in (401, 403):
                raise BlazeAuthError(f"Blaze API Key không hợp lệ hoặc bị từ chối (HTTP {status}).") from exc
            raise BlazeConnectionError(f"Máy chủ Blaze STT trả về mã lỗi HTTP {status}.") from exc
        except ConnectionClosed as exc:
            if exc.code in (1000, 1001):
                logger.debug("Blaze STT WebSocket đóng bình thường: %s", exc)
                return
            raise BlazeConnectionError(f"Mất kết nối với Blaze STT (code: {exc.code}, reason: {exc.reason})") from exc
        except (BlazeAuthError, BlazeConnectionError, BlazeTimeoutError, BlazeSTTError):
            raise
        except asyncio.CancelledError:
            logger.debug("Blaze STT stream cancelled.")
            raise
        except Exception as exc:
            logger.error("Lỗi không xác định trong Blaze STT stream: %s", exc, exc_info=True)
            raise BlazeSTTError(f"Lỗi phiên STT Blaze AI: {str(exc)}") from exc
        finally:
            self._ws = None

    async def _send_loop(self, ws: websockets.ClientConnection) -> None:
        """Consume PCM audio frames from LiveKit and stream raw bytes to Blaze AI."""
        async for item in self._input_ch:
            if isinstance(item, rtc.AudioFrame):
                pcm_bytes = bytes(item.data)
                if pcm_bytes:
                    await ws.send(pcm_bytes)
            elif isinstance(item, self._FlushSentinel):
                # LiveKit flushed segment; continue waiting for next speech frame
                continue

    async def _recv_loop(self, ws: websockets.ClientConnection) -> None:
        """Receive transcription events from Blaze AI and emit SpeechEvent into LiveKit."""
        async for raw_msg in ws:
            if not isinstance(raw_msg, str):
                continue

            try:
                data = json.loads(raw_msg)
            except Exception:
                continue

            msg_type = data.get("type")
            if msg_type == "error":
                err_msg = data.get("message") or "Lỗi từ dịch vụ nhận diện Blaze AI STT."
                raise BlazeSTTError(err_msg)

            # Extract recognized text from response
            text = (
                data.get("text")
                or data.get("transcript")
                or data.get("transcription")
                or ""
            )

            is_final = bool(
                msg_type == "final"
                or data.get("is_final")
                or data.get("final")
            )

            cleaned_text = text.strip()
            if not cleaned_text:
                continue

            ev_type = (
                stt.SpeechEventType.FINAL_TRANSCRIPT
                if is_final
                else stt.SpeechEventType.INTERIM_TRANSCRIPT
            )

            speech_data = stt.SpeechData(
                language=self._language,
                text=cleaned_text,
            )

            self._event_ch.send_nowait(
                stt.SpeechEvent(
                    type=ev_type,
                    alternatives=[speech_data],
                )
            )
