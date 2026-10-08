import logging

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import StreamingResponse

from app.schemas.voice import TTSCreateResponse, TTSInfoResponse, TTSRequest
from app.services.tts_service import BlazeTTSError, BlazeTTSService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/voice",
    tags=["Voice"],
)


@router.post(
    "/tts",
    response_model=TTSCreateResponse,
    summary="Tạo yêu cầu Text-to-Speech",
    description="Gửi văn bản đến Blaze AI để chuyển đổi thành giọng nói và nhận về TTS ID.",
)
async def create_tts(request: TTSRequest):
    service = BlazeTTSService(
        speaker_id=request.speaker_id,
        model=request.model,
        speed=request.audio_speed,
        audio_format=request.audio_format,
        audio_quality=request.audio_quality,
        normalization=request.normalization,
        language=request.language,
    )
    try:
        data = await service.create_tts(
            text=request.text,
            language=request.language,
            speaker_id=request.speaker_id or "HN-Nam-1-BL",
            model=request.model,
            audio_speed=request.audio_speed,
            audio_quality=request.audio_quality,
            audio_format=request.audio_format,
            normalization=request.normalization,
        )
        return TTSCreateResponse(id=data.get("id"))
    except BlazeTTSError as e:
        logger.error("Create TTS error: %s (status=%d)", e.message, e.status_code)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error in create TTS endpoint: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi gửi yêu cầu giọng đọc.",
        )


@router.get(
    "/tts/{tts_id}",
    response_model=TTSInfoResponse,
    summary="Lấy thông tin Text-to-Speech",
    description="Truy vấn trạng thái của một yêu cầu TTS dựa trên TTS ID.",
)
async def get_tts_info(tts_id: str):
    service = BlazeTTSService()
    try:
        data = await service.get_tts_info(tts_id)
        # Using the actual response structure from Blaze or mapping it
        return TTSInfoResponse(
            id=data.get("id", tts_id),
            status=data.get("status", "unknown"),
            audio_format=data.get("audio_format", "wav"),
            audio_quality=data.get("audio_quality", 64),
            speaker_id=data.get("speaker_id", ""),
        )
    except BlazeTTSError as e:
        logger.error("Get TTS info error: %s (status=%d)", e.message, e.status_code)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error in get TTS info endpoint: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi lấy thông tin giọng đọc.",
        )


@router.get(
    "/tts/{tts_id}/audio",
    summary="Phát Audio Text-to-Speech",
    description="Stream dữ liệu âm thanh từ Blaze AI dựa trên TTS ID.",
)
async def get_tts_audio(tts_id: str):
    service = BlazeTTSService()
    
    # We will use the stream generator directly
    async def stream_generator():
        try:
            async for chunk in service.stream_audio(tts_id):
                if chunk == b"Not Found":
                    # Cannot raise HTTPException in a generator directly for 404, but we can try 
                    pass
                yield chunk
        except Exception as e:
            logger.error("Stream error: %s", e)
            
    # Check if exists first to raise proper HTTP exception before streaming
    try:
        await service.get_tts_info(tts_id)
    except BlazeTTSError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
    
    return StreamingResponse(
        stream_generator(),
        media_type="audio/wav",  # This can be dynamic if audio_format is fetched
        headers={
            "Cache-Control": "public, max-age=86400",
        },
    )


@router.get(
    "/options",
    summary="Lấy cấu hình hỗ trợ của Blaze AI",
    description="Lấy danh sách các giọng đọc (speakers), ngôn ngữ, model được hỗ trợ.",
)
async def get_tts_options():
    service = BlazeTTSService()
    try:
        data = await service.get_tts_options()
        return data
    except BlazeTTSError as e:
        logger.error("Get TTS options error: %s (status=%d)", e.message, e.status_code)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error in get TTS options endpoint: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi lấy cấu hình TTS.",
        )
