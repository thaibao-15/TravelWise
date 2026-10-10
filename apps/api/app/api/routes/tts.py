import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Response, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.core.config import settings
from app.services.tts_service import BlazeTTSError, BlazeTTSService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/tts",
    tags=["Text to Speech"],
)


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000, description="Nội dung câu trả lời cần đọc")
    speaker_id: Optional[str] = Field(None, description="Tùy chọn giọng đọc (mặc định lấy từ cấu hình)")
    speed: Optional[str] = Field(None, description="Tốc độ đọc (ví dụ: '1', '1.1')")


class TTSStatusResponse(BaseModel):
    is_configured: bool
    speaker_id: str
    model: str
    audio_format: str
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
        model=settings.BLAZE_TTS_MODEL,
        audio_format=settings.BLAZE_TTS_AUDIO_FORMAT,
        ws_url=getattr(settings, "BLAZE_TTS_WS_URL", "wss://api.blaze.vn/v1/tts/realtime"),
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
    speed: Optional[str] = Query(None, description="Tốc độ đọc"),
):
    service = BlazeTTSService(
        speaker_id=speaker_id,
        speed=speed,
    )

    try:
        return StreamingResponse(
            service.stream_speech(text),
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": 'inline; filename="speech.mp3"',
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
    service = BlazeTTSService(
        speaker_id=request.speaker_id,
        speed=request.speed,
    )

    try:
        return StreamingResponse(
            service.stream_speech(request.text),
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": 'inline; filename="speech.mp3"',
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
