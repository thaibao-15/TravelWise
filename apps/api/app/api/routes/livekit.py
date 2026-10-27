import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_session
from app.core.config import settings
from app.models.user import User
from app.schemas.livekit import (
    LiveKitStatusResponse,
    LiveKitTokenRequest,
    LiveKitTokenResponse,
)
from app.services.conversation_service import ConversationService
from app.services.livekit_service import LiveKitError, LiveKitService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/livekit",
    tags=["LiveKit Voice"],
)


@router.get(
    "/status",
    response_model=LiveKitStatusResponse,
    summary="Kiểm tra trạng thái cấu hình LiveKit",
    description="Kiểm tra xem hệ thống đã sẵn sàng kết nối LiveKit Server/Cloud hay chưa.",
)
def get_livekit_status() -> LiveKitStatusResponse:
    """Check LiveKit readiness without leaking credentials."""
    service = LiveKitService()
    configured = service.is_configured()
    # Mask server_url to avoid revealing full project details if unconfigured
    server_url = settings.LIVEKIT_URL if configured else None
    return LiveKitStatusResponse(
        is_configured=configured,
        server_url=server_url,
        agent_name=settings.LIVEKIT_AGENT_NAME,
    )


@router.post(
    "/token",
    response_model=LiveKitTokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Cấp Access Token tham gia phòng LiveKit WebRTC",
    description="Cấp Access Token cho người dùng đã đăng nhập để kết nối vào phòng LiveKit WebRTC của TravelWise.",
    responses={
        200: {"description": "Access Token và thông tin phòng được sinh thành công."},
        400: {"description": "Tham số yêu cầu không hợp lệ."},
        401: {"description": "Chưa đăng nhập hoặc token xác thực không hợp lệ."},
        403: {"description": "Không có quyền truy cập vào cuộc trò chuyện được yêu cầu."},
        404: {"description": "Không tìm thấy cuộc trò chuyện."},
        503: {"description": "Dịch vụ LiveKit chưa được cấu hình trên máy chủ."},
    },
)
def create_livekit_token(
    request: LiveKitTokenRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> LiveKitTokenResponse:
    """Generate a LiveKit room join token for an authenticated user.

    Flow:
        1. Validate LiveKit service configuration (raises 503 if missing).
        2. Resolve conversation:
           - If conversation_id is provided: fetch and verify user ownership.
           - If not provided: create a new conversation session for current user.
        3. Determine target room name:
           - Defaults to 'travelwise_conv_{conversation_id}'.
        4. Construct participant identity ('user_{user_id}') and metadata.
        5. Generate signed JWT token with video grants (publish, subscribe).
        6. Return token and connection coordinates.
    """
    service = LiveKitService()

    try:
        service.validate_configuration()
    except LiveKitError as e:
        logger.error("LiveKit configuration error: %s", e.message)
        raise HTTPException(status_code=e.status_code, detail=e.message)

    # 1. Resolve or create conversation
    if request.conversation_id is not None:
        conversation = ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=request.conversation_id,
            current_user=current_user,
            check_ownership=True,
        )
    else:
        conversation = ConversationService.create_conversation(
            session=session,
            user_id=current_user.id,
            title="Cuộc trò chuyện thoại LiveKit",
        )

    # 2. Determine room name
    room_name = (request.room_name or "").strip() or f"travelwise_conv_{conversation.id}"

    # 3. Prepare participant metadata for the AI Agent
    metadata = {
        "conversation_id": conversation.id,
        "user_id": current_user.id,
    }

    # 4. Generate Access Token
    try:
        token = service.create_token(
            user_id=current_user.id,
            user_name=current_user.full_name or current_user.email,
            room_name=room_name,
            metadata=metadata,
        )
    except LiveKitError as e:
        logger.error("LiveKit token generation error: %s", e.message)
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception as e:
        logger.error("Unexpected error generating LiveKit token: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi tạo token phòng thoại.",
        )

    return LiveKitTokenResponse(
        server_url=service.server_url,
        token=token,
        room_name=room_name,
        identity=f"user_{current_user.id}",
        conversation_id=conversation.id,
    )
