import collections
from typing import List, Optional
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from sqlmodel import Session

from app.api.deps import get_current_user_optional, get_session
from app.models.user import User
from app.schemas.media import ChatMediaResponse
from app.services.media_service import MediaService

router = APIRouter(
    prefix="/api/v1/media",
    tags=["Media"],
)

# In-memory LRU cache for proxied images (max 100 items, expires in 24h)
_IMAGE_CACHE = collections.OrderedDict()
_MAX_CACHE_ITEMS = 100
_MAX_IMAGE_BYTES = 15 * 1024 * 1024  # 15MB max

_ALLOWED_DOMAINS = {
    "commons.wikimedia.org",
    "upload.wikimedia.org",
    "thumb.wikimedia.org",
    "images.unsplash.com",
    "i.pravatar.cc",
    "via.placeholder.com",
}


@router.get(
    "/image-proxy",
    summary="Proxy external image with CORS headers",
    description="Chuyển tiếp hình ảnh từ các nguồn cho phép (Wikimedia, Unsplash) kèm header CORS và cache để Flutter Web không bị lỗi cross-origin.",
)
async def proxy_image(
    url: str = Query(..., description="URL hình ảnh cần proxy"),
):
    """Proxy image with CORS and caching to prevent web canvas cross-origin restrictions."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Giao thức URL không hợp lệ (chỉ hỗ trợ http và https).",
        )

    domain = (parsed.hostname or "").lower()
    is_allowed = any(domain == d or domain.endswith("." + d) for d in _ALLOWED_DOMAINS)
    if not is_allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Tên miền '{domain}' không nằm trong danh sách cho phép proxy.",
        )

    # Check in-memory cache
    if url in _IMAGE_CACHE:
        content_type, body = _IMAGE_CACHE[url]
        _IMAGE_CACHE.move_to_end(url)
        return Response(
            content=body,
            media_type=content_type,
            headers={
                "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
                "Access-Control-Allow-Origin": "*",
                "X-Proxy-Cache": "HIT",
            },
        )

    headers = {
        "User-Agent": "TravelWiseApp/1.0 (https://travelwise.vn; contact: dev@travelwise.vn)",
        "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    }

    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=10.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                raise HTTPException(
                    status_code=resp.status_code,
                    detail=f"Nguồn ảnh trả về lỗi HTTP {resp.status_code}",
                )

            body = resp.content
            if len(body) > _MAX_IMAGE_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail="Dung lượng hình ảnh vượt quá giới hạn 15MB.",
                )

            content_type = resp.headers.get("content-type", "image/jpeg")

            # Store in LRU cache
            if len(_IMAGE_CACHE) >= _MAX_CACHE_ITEMS:
                _IMAGE_CACHE.popitem(last=False)
            _IMAGE_CACHE[url] = (content_type, body)

            return Response(
                content=body,
                media_type=content_type,
                headers={
                    "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
                    "Access-Control-Allow-Origin": "*",
                    "X-Proxy-Cache": "MISS",
                },
            )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Không thể tải hình ảnh từ máy chủ nguồn: {e}",
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
