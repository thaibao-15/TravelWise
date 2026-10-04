import logging
from typing import List, Optional

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User

logger = logging.getLogger(__name__)


class ConversationService:
    """Service handling CRUD operations for Conversations and Messages."""

    @staticmethod
    def create_conversation(
        session: Session,
        user_id: Optional[int] = None,
        title: Optional[str] = None,
    ) -> Conversation:
        """Create a new conversation session."""
        now = _utcnow()
        conv = Conversation(
            user_id=user_id,
            title=title or "Cuộc trò chuyện mới",
            created_at=now,
            updated_at=now,
        )
        session.add(conv)
        session.commit()
        session.refresh(conv)
        return conv

    @staticmethod
    def get_conversation_by_id(
        session: Session,
        conversation_id: int,
        current_user: Optional[User] = None,
        check_ownership: bool = True,
    ) -> Conversation:
        """Fetch a conversation by ID, checking existence and ownership."""
        conv = session.get(Conversation, conversation_id)
        if not conv:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy cuộc trò chuyện với ID {conversation_id}",
            )

        if check_ownership and conv.user_id is not None:
            if not current_user:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Vui lòng đăng nhập để truy cập cuộc trò chuyện này.",
                )
            if conv.user_id != current_user.id and current_user.role != "ADMIN":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Bạn không có quyền truy cập cuộc trò chuyện này.",
                )

        return conv

    @staticmethod
    def list_user_conversations(
        session: Session,
        user_id: int,
        skip: int = 0,
        limit: int = 50,
    ) -> List[Conversation]:
        """List all conversations owned by a user, ordered by recent update."""
        statement = (
            select(Conversation)
            .where(Conversation.user_id == user_id)
            .order_by(Conversation.updated_at.desc())
            .offset(skip)
            .limit(limit)
        )
        return list(session.exec(statement).all())

    @staticmethod
    def update_conversation_timestamp(
        session: Session,
        conversation: Conversation,
    ) -> Conversation:
        """Update the conversation's updated_at timestamp to now."""
        conversation.updated_at = _utcnow()
        session.add(conversation)
        session.commit()
        session.refresh(conversation)
        return conversation

    @staticmethod
    def delete_conversation(
        session: Session,
        conversation_id: int,
        current_user: User,
    ) -> None:
        """Delete a conversation, verifying ownership first."""
        conv = ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=conversation_id,
            current_user=current_user,
            check_ownership=True,
        )
        session.delete(conv)
        session.commit()

    @staticmethod
    def save_message(
        session: Session,
        conversation_id: int,
        sender: str,
        content: str,
        audio_url: Optional[str] = None,
    ) -> Message:
        """Save a single message (USER or AI) to the database."""
        clean_sender = sender.upper()
        if clean_sender not in ("USER", "AI"):
            clean_sender = "USER"

        msg = Message(
            conversation_id=conversation_id,
            sender=clean_sender,
            content=content,
            audio_url=audio_url,
            created_at=_utcnow(),
        )
        session.add(msg)
        session.commit()
        session.refresh(msg)
        return msg

    @staticmethod
    def get_messages_by_conversation(
        session: Session,
        conversation_id: int,
        current_user: Optional[User] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[Message]:
        """Fetch all messages for a conversation in chronological order."""
        # Verify conversation existence and ownership
        ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=conversation_id,
            current_user=current_user,
            check_ownership=True,
        )

        statement = (
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.asc(), Message.id.asc())
            .offset(skip)
            .limit(limit)
        )
        return list(session.exec(statement).all())

    @staticmethod
    def get_recent_messages(
        session: Session,
        conversation_id: int,
        limit: int = 10,
    ) -> List[Message]:
        """Fetch the most recent N messages, returned in chronological order for LLM context."""
        statement = (
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.desc(), Message.id.desc())
            .limit(limit)
        )
        recent = list(session.exec(statement).all())
        # Reverse to return chronological order (oldest to newest among the recent ones)
        recent.reverse()
        return recent
