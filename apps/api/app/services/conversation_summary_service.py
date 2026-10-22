"""Conversation summary generation and persistence."""

import logging
from threading import Lock
from typing import ClassVar

from langchain_core.messages import HumanMessage, SystemMessage
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.conversation import Conversation
from app.models.conversation_summary import ConversationSummary
from app.models.message import Message
from app.rag.llm import extract_response_text, get_chat_llm

logger = logging.getLogger(__name__)


SUMMARY_SYSTEM_PROMPT = """Bạn là bộ nhớ tóm tắt hội thoại của TravelWise.
Hãy hợp nhất summary cũ (nếu có) với các tin nhắn mới và trả về một summary tiếng Việt
ngắn gọn, dễ đọc, chỉ giữ thông tin hữu ích cho những lần trò chuyện sau:
- sở thích du lịch, địa điểm quan tâm, ngân sách, thời gian và yêu cầu chuyến đi;
- lịch trình đã thống nhất;
- câu hỏi hoặc yêu cầu chưa được giải quyết;
- các thông tin quan trọng khác do người dùng trực tiếp cung cấp.

Quy tắc bắt buộc:
1. Không suy diễn hoặc biến đề xuất/suy đoán của AI thành thông tin chắc chắn của người dùng.
2. Khi người dùng thay đổi yêu cầu, giữ giá trị mới nhất và bỏ giá trị cũ nếu có căn cứ rõ ràng.
3. Bỏ lời chào, nội dung lặp lại và chi tiết không hữu ích.
4. Không đưa API key, mật khẩu, token hoặc bí mật vào summary.
5. Chỉ trả về summary tiếng Việt, không thêm lời dẫn, tiêu đề hay Markdown không cần thiết.
"""


class ConversationSummaryError(RuntimeError):
    """Raised when a summary cannot be generated or persisted."""


class ConversationSummaryService:
    """Create, update, and retrieve one summary per conversation."""

    SUMMARY_AFTER_MESSAGES = 8
    MAX_SUMMARY_LENGTH = 6000
    MAX_RECENT_SUMMARIES = 3
    _conversation_locks: ClassVar[dict[int, Lock]] = {}
    _locks_guard = Lock()

    @classmethod
    def _lock_for(cls, conversation_id: int) -> Lock:
        with cls._locks_guard:
            lock = cls._conversation_locks.get(conversation_id)
            if lock is None:
                lock = Lock()
                cls._conversation_locks[conversation_id] = lock
            return lock

    @staticmethod
    def get_summary(
        session: Session,
        conversation_id: int,
        user_id: int | None = None,
    ) -> ConversationSummary | None:
        """Return a summary only when it belongs to the requested conversation/user."""
        statement = (
            select(ConversationSummary)
            .join(Conversation, Conversation.id == ConversationSummary.conversation_id)
            .where(
                ConversationSummary.conversation_id == conversation_id,
                Conversation.user_id == user_id,
            )
        )
        return session.exec(statement).first()

    @classmethod
    def get_recent_user_summaries(
        cls,
        session: Session,
        user_id: int | None,
        exclude_conversation_id: int | None = None,
    ) -> list[ConversationSummary]:
        """Load a small, ownership-filtered set of summaries for continuity."""
        if user_id is None:
            return []

        statement = (
            select(ConversationSummary)
            .join(Conversation, Conversation.id == ConversationSummary.conversation_id)
            .where(Conversation.user_id == user_id)
            .order_by(ConversationSummary.updated_at.desc())
            .limit(cls.MAX_RECENT_SUMMARIES)
        )
        if exclude_conversation_id is not None:
            statement = statement.where(
                ConversationSummary.conversation_id != exclude_conversation_id
            )
        return list(session.exec(statement).all())

    @staticmethod
    def get_unsummarized_messages(
        session: Session,
        conversation_id: int,
        last_summarized_message_id: int | None,
    ) -> list[Message]:
        statement = select(Message).where(Message.conversation_id == conversation_id)
        if last_summarized_message_id is not None:
            statement = statement.where(Message.id > last_summarized_message_id)
        statement = statement.order_by(Message.id.asc())
        return list(session.exec(statement).all())

    @classmethod
    def build_context_history(
        cls,
        summary: ConversationSummary | None,
        recent_summaries: list[ConversationSummary],
    ) -> list[HumanMessage]:
        """Represent persisted summaries as bounded conversational context."""
        context: list[HumanMessage] = []
        if summary and summary.summary.strip():
            context.append(
                HumanMessage(
                    content=f"Tóm tắt cuộc trò chuyện hiện tại:\n{summary.summary[: cls.MAX_SUMMARY_LENGTH]}"
                )
            )
        for previous in recent_summaries:
            if previous.summary.strip():
                context.append(
                    HumanMessage(
                        content=f"Tóm tắt cuộc trò chuyện trước:\n{previous.summary[: cls.MAX_SUMMARY_LENGTH]}"
                    )
                )
        return context

    @classmethod
    def maybe_update_summary(
        cls,
        session: Session,
        conversation_id: int,
        user_id: int | None = None,
    ) -> ConversationSummary | None:
        """Update a summary after enough new messages, without breaking chat on failure."""
        lock = cls._lock_for(conversation_id)
        with lock:
            conversation = session.get(Conversation, conversation_id)
            if conversation is None or conversation.user_id != user_id:
                raise ConversationSummaryError(
                    "Conversation summary access is not authorized"
                )
            current = cls.get_summary(session, conversation_id, user_id=user_id)
            last_id = current.last_summarized_message_id if current else None
            new_messages = cls.get_unsummarized_messages(
                session, conversation_id, last_id
            )
            if len(new_messages) < cls.SUMMARY_AFTER_MESSAGES:
                return current

            transcript = "\n".join(
                f"{message.sender}: {(message.content or '').strip()}"
                for message in new_messages
                if (message.content or "").strip()
            )
            if not transcript:
                return current

            try:
                response = get_chat_llm(temperature=0.2).invoke(
                    [
                        SystemMessage(content=SUMMARY_SYSTEM_PROMPT),
                        HumanMessage(
                            content=(
                                f"SUMMARY CŨ:\n{current.summary if current else '(chưa có)'}\n\n"
                                f"TIN NHẮN MỚI:\n{transcript}"
                            )
                        ),
                    ]
                )
                summary_text = extract_response_text(
                    getattr(response, "content", response)
                ).strip()
                if not summary_text:
                    raise ConversationSummaryError("LLM returned an empty summary")

                now = _utcnow()
                if current is None:
                    current = ConversationSummary(
                        conversation_id=conversation_id,
                        summary=summary_text[: cls.MAX_SUMMARY_LENGTH],
                        last_summarized_message_id=new_messages[-1].id,
                        updated_at=now,
                    )
                else:
                    current.summary = summary_text[: cls.MAX_SUMMARY_LENGTH]
                    current.last_summarized_message_id = new_messages[-1].id
                    current.updated_at = now
                session.add(current)
                session.commit()
                session.refresh(current)
                return current
            except ConversationSummaryError:
                session.rollback()
                raise
            except Exception as exc:
                session.rollback()
                logger.error(
                    "Conversation summary update failed for conversation %s: %s",
                    conversation_id,
                    type(exc).__name__,
                )
                raise ConversationSummaryError(
                    "Conversation summary update failed"
                ) from exc
