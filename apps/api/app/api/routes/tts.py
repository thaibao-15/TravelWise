import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Response, status
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


@router.get(
    "/status",
    response_model=TTSStatusResponse,
    summary="Kiểm tra trạng thái cấu hình Blaze TTS",
    description="Kiểm tra xem hệ thống đã sẵn sàng phát âm thanh Text-to-Speech hay chưa.",
)
def get_tts_status() -> TTSStatusResponse:
    has_key = bool(settings.BLAZE_API_KEY and settings.BLAZE_API_KEY.strip())
    return TTSStatusResponse(
        is_configured=has_key,
        speaker_id=settings.BLAZE_TTS_SPEAKER_ID,
        model=settings.BLAZE_TTS_MODEL,
        audio_format=settings.BLAZE_TTS_AUDIO_FORMAT,
    )


@router.post(
    "",
    summary="Tổng hợp giọng nói Text-to-Speech",
    description="Chuyển đổi nội dung văn bản của AI response thành âm thanh giọng đọc tự nhiên (WAV).",
    responses={
        200: {
            "content": {"audio/wav": {}},
            "description": "Stream âm thanh WAV để phát trực tiếp trên trình duyệt.",
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
        audio_bytes = await service.synthesize_speech(request.text)
        return Response(
            content=audio_bytes,
            media_type="audio/wav",
            headers={
                "Content-Disposition": 'inline; filename="speech.wav"',
                "Cache-Control": "public, max-age=86400",
            },
        )
    except BlazeTTSError as e:
        logger.error("TTS synthesis error: %s (status=%d)", e.message, e.status_code)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error in TTS endpoint: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi tạo âm thanh giọng đọc.",
        )
