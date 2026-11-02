import asyncio
import json
import logging
from typing import Optional

from fastapi import (
    APIRouter,
    HTTPException,
    Query,
    Response,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatus, WebSocketException

from app.core.config import settings
from app.services.tts_service import BlazeTTSError, BlazeTTSService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/tts",
    tags=["Text to Speech"],
)


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000, description="Nội dung câu trả lời cần đọc")
    speaker_id: Optional[str] = Field(None, description="Tùy chọn giọng đọc (mã giọng ví dụ: 'HN-Nam-2-BL')")
    voice: Optional[str] = Field(None, description="Tùy chọn giọng đọc (alias cho speaker_id)")
    model: Optional[str] = Field(None, description="Tùy chọn model TTS realtime (ví dụ: 'blaze-tts-2-realtime')")
    speed: Optional[str] = Field(None, description="Tốc độ đọc (ví dụ: '1.0', '1.1')")
    response_format: Optional[str] = Field(None, description="Định dạng âm thanh: 'mp3', 'opus', 'wav', 'pcm'")
    sample_rate: Optional[int] = Field(None, description="Tần số lấy mẫu (ví dụ: 24000)")
    language: Optional[str] = Field(None, description="Ngôn ngữ (mặc định: 'vi')")


class TTSStatusResponse(BaseModel):
    is_configured: bool
    speaker_id: str
    voice: str
    model: str
    audio_format: str
    sample_rate: int
    speed: float
    language: str
    ws_url: str


@router.get(
    "/status",
    response_model=TTSStatusResponse,
    summary="Kiểm tra trạng thái cấu hình Blaze TTS Realtime",
    description="Kiểm tra xem hệ thống đã sẵn sàng phát âm thanh Text-to-Speech Realtime hay chưa.",
)
def get_tts_status() -> TTSStatusResponse:
    has_key = bool(settings.BLAZE_API_KEY and settings.BLAZE_API_KEY.strip())
    return TTSStatusResponse(
        is_configured=has_key,
        speaker_id=settings.BLAZE_TTS_SPEAKER_ID,
        voice=settings.BLAZE_TTS_SPEAKER_ID,
        model=settings.BLAZE_TTS_MODEL,
        audio_format=settings.BLAZE_TTS_AUDIO_FORMAT,
        sample_rate=settings.BLAZE_TTS_SAMPLE_RATE,
        speed=float(settings.BLAZE_TTS_SPEED),
        language=getattr(settings, "BLAZE_TTS_LANGUAGE", "vi"),
        ws_url=settings.BLAZE_TTS_WS_URL,
    )


@router.head(
    "/stream",
    summary="Kiểm tra endpoint stream TTS",
)
async def head_stream_text_to_speech():
    return Response(
        status_code=status.HTTP_200_OK,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "public, max-age=86400",
            "Accept-Ranges": "bytes",
        },
    )


@router.get(
    "/stream",
    summary="Stream giọng đọc Realtime qua HTTP (GET)",
    description="Stream trực tiếp các chunk âm thanh MP3 từ Blaze TTS Realtime để thẻ audio phát tức thì (TTFB < 500ms).",
    responses={
        200: {
            "content": {"audio/mpeg": {}},
            "description": "Stream âm thanh MP3 realtime dạng chunked transfer.",
        },
        400: {"description": "Nội dung văn bản không hợp lệ."},
        401: {"description": "Chưa cấu hình API Key hoặc không có quyền truy cập."},
        502: {"description": "Dịch vụ Blaze TTS không khả dụng."},
    },
)
async def stream_text_to_speech_get(
    text: str = Query(..., min_length=1, max_length=5000, description="Nội dung câu cần đọc"),
    speaker_id: Optional[str] = Query(None, description="Tùy chọn giọng đọc"),
    voice: Optional[str] = Query(None, description="Tùy chọn giọng đọc (alias cho speaker_id)"),
    speed: Optional[str] = Query(None, description="Tốc độ đọc (ví dụ: '1.0')"),
    model: Optional[str] = Query(None, description="Tùy chọn model"),
    language: Optional[str] = Query(None, description="Tùy chọn ngôn ngữ ('vi', 'en', ...)"),
    response_format: Optional[str] = Query(None, description="Định dạng âm thanh ('mp3', 'wav', ...)"),
    sample_rate: Optional[int] = Query(None, description="Tần số lấy mẫu (Hz)"),
):
    chosen_voice = voice or speaker_id
    service = BlazeTTSService(
        voice=chosen_voice,
        speed=speed,
        model=model,
        language=language,
        response_format=response_format,
        sample_rate=sample_rate,
    )

    media_type = "audio/mpeg"
    if response_format in ("wav", "audio/wav"):
        media_type = "audio/wav"
    elif response_format in ("opus", "audio/opus"):
        media_type = "audio/opus"

    try:
        return StreamingResponse(
            service.stream_speech(text),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="speech.{response_format or "mp3"}"',
                "Cache-Control": "public, max-age=86400",
                "Accept-Ranges": "bytes",
            },
        )
    except BlazeTTSError as e:
        logger.error("TTS stream error: %s (status=%d)", e.message, e.status_code)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error in TTS stream GET endpoint: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi tạo âm thanh giọng đọc.",
        )


@router.post(
    "",
    summary="Tổng hợp & stream giọng nói Realtime Text-to-Speech (POST)",
    description="Chuyển đổi nội dung văn bản thành luồng âm thanh MP3 mượt mà với độ trễ tối thiểu.",
    responses={
        200: {
            "content": {"audio/mpeg": {}},
            "description": "Stream âm thanh MP3 realtime để phát trực tiếp trên trình duyệt.",
        },
        400: {"description": "Nội dung văn bản không hợp lệ."},
        401: {"description": "Chưa cấu hình API Key hoặc không có quyền truy cập."},
        502: {"description": "Dịch vụ Blaze TTS không khả dụng."},
    },
)
async def synthesize_text_to_speech(request: TTSRequest):
    chosen_voice = request.voice or request.speaker_id
    service = BlazeTTSService(
        voice=chosen_voice,
        speed=request.speed,
        model=request.model,
        language=request.language,
        response_format=request.response_format,
        sample_rate=request.sample_rate,
    )

    media_type = "audio/mpeg"
    fmt = request.response_format or "mp3"
    if fmt in ("wav", "audio/wav"):
        media_type = "audio/wav"
    elif fmt in ("opus", "audio/opus"):
        media_type = "audio/opus"

    try:
        return StreamingResponse(
            service.stream_speech(request.text),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="speech.{fmt}"',
                "Cache-Control": "public, max-age=86400",
                "Accept-Ranges": "bytes",
            },
        )
    except BlazeTTSError as e:
        logger.error("TTS synthesis error: %s (status=%d)", e.message, e.status_code)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error in TTS POST endpoint: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi tạo âm thanh giọng đọc.",
        )


@router.websocket("/ws")
async def websocket_tts_endpoint(
    websocket: WebSocket,
    api_key: Optional[str] = Query(None),
    model: Optional[str] = Query(None),
    voice: Optional[str] = Query(None),
    speaker_id: Optional[str] = Query(None),
    language: Optional[str] = Query(None),
    response_format: Optional[str] = Query(None),
    sample_rate: Optional[int] = Query(None),
    speed: Optional[float] = Query(None),
    mode: Optional[str] = Query(None),
):
    """Native Realtime Blaze TTS WebSocket Proxy Endpoint.

    Flow:
        1. Client connects via WebSocket to /api/v1/tts/ws with query options.
        2. Backend connects to Blaze TTS Realtime (wss://api.blaze.vn/v1/audio/speech/realtime).
        3. Blaze sends 'session.created' with active configuration -> forwarded to client.
        4. Client sends:
            - 'speech.create': {"type": "speech.create", "input": text, ...overrides}
            - 'input_text.append': {"type": "input_text.append", "text": token} (mode=stream)
            - 'input_text.flush': {"type": "input_text.flush"} (mode=stream)
            - 'session.update': {"type": "session.update", "session": {...}}
            - 'session.close': {"type": "session.close"}
        5. Blaze sends:
            - 'speech.started'
            - 'speech.audio.started'
            - binary audio frames (forwarded as binary WebSocket frames)
            - 'speech.audio.done'
            - 'speech.done'
            - 'error'
            - 'session.closed'
    """
    await websocket.accept()

    # Determine API key (client header/param or server-configured .env)
    auth_header = websocket.headers.get("authorization")
    client_token = None
    if auth_header and auth_header.lower().startswith("bearer "):
        client_token = auth_header[7:].strip()
    effective_api_key = api_key or client_token or settings.BLAZE_API_KEY

    if not effective_api_key or not effective_api_key.strip():
        await websocket.send_json({
            "type": "error",
            "error": {
                "message": "Chưa cấu hình BLAZE_API_KEY trong file .env hoặc query param.",
                "type": "unauthorized",
                "code": 401,
            },
        })
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    chosen_voice = voice or speaker_id or settings.BLAZE_TTS_SPEAKER_ID
    service = BlazeTTSService(
        api_key=effective_api_key,
        voice=chosen_voice,
        model=model or settings.BLAZE_TTS_MODEL,
        speed=speed if speed is not None else settings.BLAZE_TTS_SPEED,
        language=language or getattr(settings, "BLAZE_TTS_LANGUAGE", "vi"),
        response_format=response_format or settings.BLAZE_TTS_AUDIO_FORMAT,
        sample_rate=sample_rate or settings.BLAZE_TTS_SAMPLE_RATE,
        mode=mode,
    )

    upstream_url = service.connection_url()
    upstream_headers = {"Authorization": f"Bearer {effective_api_key.strip()}"}

    blaze_ws = None
    try:
        blaze_ws = await websockets.connect(
            upstream_url,
            additional_headers=upstream_headers,
            ping_interval=None,
        )
    except InvalidStatus as e:
        http_code = getattr(e.response, "status_code", 502)
        err_type = "unauthorized" if http_code in (401, 403) else ("rate_limit_error" if http_code == 429 else "api_error")
        await websocket.send_json({
            "type": "error",
            "error": {
                "message": f"Không thể kết nối đến máy chủ Blaze TTS (HTTP {http_code}).",
                "type": err_type,
                "code": http_code,
            },
        })
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        return
    except Exception as e:
        logger.error("Failed connecting to upstream Blaze TTS: %s", e)
        await websocket.send_json({
            "type": "error",
            "error": {
                "message": f"Lỗi kết nối máy chủ Blaze TTS: {str(e)}",
                "type": "connection_error",
                "code": 502,
            },
        })
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        return

    # Forwarding tasks between client and upstream Blaze
    async def client_to_blaze():
        try:
            while True:
                message = await websocket.receive()
                if "text" in message and message["text"]:
                    await blaze_ws.send(message["text"])
                elif "bytes" in message and message["bytes"]:
                    await blaze_ws.send(message["bytes"])
        except (WebSocketDisconnect, ConnectionClosed):
            pass
        except Exception as exc:
            logger.debug("client_to_blaze terminated: %s", exc)

    async def blaze_to_client():
        try:
            while True:
                frame = await blaze_ws.recv()
                if isinstance(frame, bytes):
                    await websocket.send_bytes(frame)
                elif isinstance(frame, str):
                    await websocket.send_text(frame)
                    # If server acknowledged session closure, close client socket
                    try:
                        parsed = json.loads(frame)
                        if parsed.get("type") == "session.closed":
                            await websocket.close()
                            break
                    except Exception:
                        pass
        except (WebSocketDisconnect, ConnectionClosed):
            pass
        except Exception as exc:
            logger.debug("blaze_to_client terminated: %s", exc)

    c2b_task = asyncio.create_task(client_to_blaze())
    b2c_task = asyncio.create_task(blaze_to_client())

    done, pending = await asyncio.wait(
        [c2b_task, b2c_task],
        return_when=asyncio.FIRST_COMPLETED,
    )

    for task in pending:
        task.cancel()

    try:
        await blaze_ws.close()
    except Exception:
        pass
