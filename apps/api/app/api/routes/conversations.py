from typing import List, Optional
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_session
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.schemas.conversation import ConversationCreate, ConversationRead, MessageRead
from app.services.conversation_service import ConversationService

router = APIRouter(
    prefix="/api/v1/conversations",
    tags=["Conversations"],
)


@router.post(
    "/",
    response_model=ConversationRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new conversation",
    description="Khởi tạo một cuộc trò chuyện mới cho người dùng đã đăng nhập.",
)
def create_conversation(
    data: Optional[ConversationCreate] = None,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Conversation:
    title = data.title if data else None
    return ConversationService.create_conversation(
        session=session,
        user_id=current_user.id,
        title=title,
    )


@router.get(
    "/",
    response_model=List[ConversationRead],
    status_code=status.HTTP_200_OK,
    summary="List user conversations",
    description="Lấy danh sách các cuộc trò chuyện của người dùng hiện tại, sắp xếp theo thời gian mới nhất.",
)
def list_conversations(
    skip: int = 0,
    limit: int = 50,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> List[Conversation]:
    return ConversationService.list_user_conversations(
        session=session,
        user_id=current_user.id,
        skip=skip,
        limit=limit,
    )


@router.get(
    "/{conversation_id}",
    response_model=ConversationRead,
    status_code=status.HTTP_200_OK,
    summary="Get conversation details",
    description="Lấy thông tin chi tiết một cuộc trò chuyện theo ID (chỉ xem được cuộc trò chuyện của chính mình).",
)
def get_conversation(
    conversation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Conversation:
    return ConversationService.get_conversation_by_id(
        session=session,
        conversation_id=conversation_id,
        current_user=current_user,
        check_ownership=True,
    )


@router.get(
    "/{conversation_id}/messages",
    response_model=List[MessageRead],
    status_code=status.HTTP_200_OK,
    summary="Get conversation message history",
    description="Lấy toàn bộ lịch sử tin nhắn trong cuộc trò chuyện theo thứ tự thời gian.",
)
def get_conversation_messages(
    conversation_id: int,
    skip: int = 0,
    limit: int = 100,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> List[Message]:
    return ConversationService.get_messages_by_conversation(
        session=session,
        conversation_id=conversation_id,
        current_user=current_user,
        skip=skip,
        limit=limit,
    )


@router.delete(
    "/{conversation_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete conversation",
    description="Xóa một cuộc trò chuyện cùng tất cả tin nhắn liên quan (chỉ xóa được cuộc trò chuyện của chính mình).",
)
def delete_conversation(
    conversation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> None:
    ConversationService.delete_conversation(
        session=session,
        conversation_id=conversation_id,
        current_user=current_user,
    )
