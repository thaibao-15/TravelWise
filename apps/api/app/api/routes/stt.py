import asyncio
import json
import logging
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from pydantic import BaseModel

from app.core.config import settings
from app.services.blaze_stt_service import BlazeSTTError, BlazeSTTService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/stt",
    tags=["Speech to Text"],
)


class STTStatusResponse(BaseModel):
    is_configured: bool
    model: str
    language: str
    ws_url: str


@router.get(
    "/status",
    response_model=STTStatusResponse,
    summary="Kiểm tra trạng thái cấu hình Blaze STT",
    description="Kiểm tra xem hệ thống đã cấu hình Blaze API Key cho Speech-to-Text hay chưa.",
)
def get_stt_status() -> STTStatusResponse:
    has_key = bool(settings.BLAZE_API_KEY and settings.BLAZE_API_KEY.strip())
    return STTStatusResponse(
        is_configured=has_key,
        model=settings.BLAZE_STT_MODEL,
        language=settings.BLAZE_STT_LANGUAGE,
        ws_url=settings.BLAZE_STT_WS_URL,
    )


@router.websocket("/ws")
async def websocket_stt_endpoint(websocket: WebSocket):
    """Native Realtime Blaze STT WebSocket Proxy Endpoint.

    Flow:
        1. Browser connects via WebSocket to /api/v1/stt/ws.
        2. Backend connects to Blaze AI STT Realtime (wss://api.blaze.vn/v1/stt/realtime).
        3. Backend sends authentication frame {"token": BLAZE_API_KEY, "language": "vi", "model": "stt-stream-1.5"}.
        4. When Blaze responds "ready", backend acknowledges browser with "ready".
        5. Browser streams downsampled 16kHz 16-bit mono PCM chunks directly to Blaze.
        6. Blaze streams realtime partial and final transcripts directly back to browser.
        7. Zero delay, zero polling, true sub-second speech recognition.
    """
    await websocket.accept()

    # 1. Check configuration
    if not settings.BLAZE_API_KEY or not settings.BLAZE_API_KEY.strip():
        await websocket.send_json({
            "type": "error",
            "message": "Chưa cấu hình BLAZE_API_KEY trong file .env. Vui lòng thêm BLAZE_API_KEY để sử dụng tính năng STT.",
        })
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    service = BlazeSTTService()
    blaze_ws = None

    try:
        blaze_ws = await service.connect()
        await websocket.send_json({
            "type": "status",
            "status": "ready",
            "message": "Đã kết nối trực tiếp Blaze AI STT Realtime.",
        })
    except BlazeSTTError as e:
        logger.warning("Blaze STT connection error: %s", e.message)
        await websocket.send_json({"type": "error", "message": e.message})
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        return
    except Exception as e:
        logger.error("Unexpected error connecting to Blaze STT: %s", e)
        await websocket.send_json({"type": "error", "message": "Không thể kết nối đến máy chủ nhận dạng Blaze AI."})
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
        return

    # 2. Bi-directional low-latency forwarding
    async def client_to_blaze():
        try:
            while True:
                message = await websocket.receive()
                if "bytes" in message and message["bytes"]:
                    await blaze_ws.send(message["bytes"])
                elif "text" in message and message["text"]:
                    try:
                        cmd = json.loads(message["text"])
                        if cmd.get("type") in ("stop", "end"):
                            logger.info("Client requested STT stop")
                            break
                    except json.JSONDecodeError:
                        pass
        except WebSocketDisconnect:
            pass
        except Exception as e:
            logger.debug("client_to_blaze completed: %s", e)

    async def blaze_to_client():
        try:
            while True:
                msg = await blaze_ws.recv()
                if isinstance(msg, str):
                    parsed = BlazeSTTService.parse_transcript_message(msg)
                    if parsed:
                        await websocket.send_json(parsed)
        except Exception as e:
            logger.debug("blaze_to_client completed: %s", e)

    task1 = asyncio.create_task(client_to_blaze())
    task2 = asyncio.create_task(blaze_to_client())

    try:
        await asyncio.wait([task1, task2], return_when=asyncio.FIRST_COMPLETED)
        for t in [task1, task2]:
            t.cancel()
    finally:
        if blaze_ws:
            try:
                await blaze_ws.close()
            except Exception:
                pass
        try:
            await websocket.send_json({"type": "status", "status": "stopped"})
            await websocket.close()
        except Exception:
            pass
