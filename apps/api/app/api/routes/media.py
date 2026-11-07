from typing import List, Optional
import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from fastapi.responses import Response
from sqlmodel import Session

from app.api.deps import get_current_user_optional, get_session
from app.models.user import User
from app.schemas.media import ChatMediaResponse
from app.services.media_service import MediaService

router = APIRouter(
    prefix="/api/v1/media",
    tags=["Media"],
)


@router.post(
    "/upload",
    response_model=ChatMediaResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload image or video for chat attachments",
    description="Tải lên tệp hình ảnh hoặc video từ thiết bị của người dùng để gửi trong tin nhắn trò chuyện.",
)
async def upload_chat_media(
    file: UploadFile = File(..., description="Tệp hình ảnh hoặc video đính kèm"),
    media_type: Optional[str] = Form(default=None, description="Tùy chọn: 'image' hoặc 'video'"),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> ChatMediaResponse:
    """Securely uploads an image or video file and returns its public URL and metadata."""
    return await MediaService.save_upload(file=file, media_type=media_type)


@router.get(
    "/suggest",
    response_model=List[ChatMediaResponse],
    status_code=status.HTTP_200_OK,
    summary="Suggest destination media for a query",
    description="Gợi ý hình ảnh hoặc video địa điểm du lịch dựa trên từ khóa tìm kiếm hoặc câu hỏi của người dùng.",
)
def suggest_destination_media(
    q: str = Query(..., min_length=2, description="Từ khóa hoặc câu hỏi của người dùng"),
    session: Session = Depends(get_session),
) -> List[ChatMediaResponse]:
    """Retrieve verified destination media for user questions."""
    return MediaService.suggest_media_for_query(session=session, query=q)


@router.get(
    "/image-proxy",
    status_code=status.HTTP_200_OK,
    summary="Proxy destination images (Wikimedia, OSM)",
    description="Chuyển tiếp và cache ảnh từ Wikimedia/OSM để vượt qua rào cản CORS và User-Agent trên client.",
)
async def proxy_image(url: str = Query(..., description="Target image URL")):
    """Proxies images with a standard User-Agent and stream response."""
    if not url.startswith("http://") and not url.startswith("https://"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid image URL protocol",
        )

    headers = {
        "User-Agent": "TravelWise/1.0 (Travel Planner App; contact@travelwise.vn)",
        "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
    }

    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=12.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                raise HTTPException(
                    status_code=resp.status_code,
                    detail=f"Remote image returned status {resp.status_code}",
                )

            media_type = resp.headers.get("content-type", "image/jpeg")
            return Response(
                content=resp.content,
                media_type=media_type,
                headers={
                    "Cache-Control": "public, max-age=604800, immutable",
                },
            )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to fetch remote image: {str(exc)}",
        ) from exc

