import unittest
from unittest.mock import Mock, patch

from sqlalchemy import create_engine
from sqlmodel import Session, select

from app.models.conversation import Conversation
from app.models.conversation_summary import ConversationSummary
from app.models.message import Message
from app.models.user import User
from app.services.conversation_summary_service import (
    ConversationSummaryError,
    ConversationSummaryService,
)


class TestConversationSummaryService(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}
        )
        for model in (User, Conversation, Message, ConversationSummary):
            model.metadata.create_all(cls.engine, tables=[model.__table__])

    def setUp(self):
        with Session(self.engine) as session:
            user = User(email=f"summary-{id(self)}@example.com")
            session.add(user)
            session.commit()
            session.refresh(user)
            conversation = Conversation(user_id=user.id, title="Summary test")
            session.add(conversation)
            session.commit()
            session.refresh(conversation)
            self.user_id = user.id
            self.conversation_id = conversation.id

    def _add_messages(self, count: int) -> None:
        with Session(self.engine) as session:
            for index in range(count):
                session.add(
                    Message(
                        conversation_id=self.conversation_id,
                        sender="USER" if index % 2 == 0 else "AI",
                        content=f"message {index}",
                    )
                )
            session.commit()

    @patch("app.services.conversation_summary_service.get_chat_llm")
    def test_creates_summary_and_tracks_last_message(self, get_llm):
        self._add_messages(8)
        get_llm.return_value.invoke.return_value = Mock(
            content="Người dùng muốn đi Đà Nẵng trong 3 ngày."
        )

        with Session(self.engine) as session:
            last_message_id = session.exec(
                select(Message.id)
                .where(Message.conversation_id == self.conversation_id)
                .order_by(Message.id.desc())
            ).first()
            summary = ConversationSummaryService.maybe_update_summary(
                session, self.conversation_id, self.user_id
            )
            self.assertIsNotNone(summary)
            self.assertEqual(summary.last_summarized_message_id, last_message_id)
            self.assertEqual(
                summary.summary, "Người dùng muốn đi Đà Nẵng trong 3 ngày."
            )
            get_llm.return_value.invoke.assert_called_once()

    @patch("app.services.conversation_summary_service.get_chat_llm")
    def test_updates_existing_summary_and_preserves_old_summary_in_prompt(
        self, get_llm
    ):
        self._add_messages(8)
        get_llm.return_value.invoke.return_value = Mock(content="Summary mới")

        with Session(self.engine) as session:
            old = ConversationSummary(
                conversation_id=self.conversation_id,
                summary="Ngân sách 5 triệu.",
                last_summarized_message_id=2,
            )
            session.add(old)
            session.commit()
            last_message_id = session.exec(
                select(Message.id)
                .where(Message.conversation_id == self.conversation_id)
                .order_by(Message.id.desc())
            ).first()
            ConversationSummaryService.maybe_update_summary(
                session, self.conversation_id, self.user_id
            )
            session.refresh(old)
            self.assertEqual(old.summary, "Summary mới")
            self.assertEqual(old.last_summarized_message_id, last_message_id)

        prompt = get_llm.return_value.invoke.call_args.args[0][1].content
        self.assertIn("Ngân sách 5 triệu.", prompt)

    @patch("app.services.conversation_summary_service.get_chat_llm")
    def test_skips_when_there_are_not_enough_new_messages(self, get_llm):
        self._add_messages(7)

        with Session(self.engine) as session:
            self.assertIsNone(
                ConversationSummaryService.maybe_update_summary(
                    session, self.conversation_id, self.user_id
                )
            )
        get_llm.assert_not_called()

    @patch("app.services.conversation_summary_service.get_chat_llm")
    def test_skips_when_all_messages_are_already_summarized(self, get_llm):
        self._add_messages(8)

        with Session(self.engine) as session:
            last_message_id = session.exec(
                select(Message.id)
                .where(Message.conversation_id == self.conversation_id)
                .order_by(Message.id.desc())
            ).first()
            session.add(
                ConversationSummary(
                    conversation_id=self.conversation_id,
                    summary="Summary hiện tại",
                    last_summarized_message_id=last_message_id,
                )
            )
            session.commit()
            summary = ConversationSummaryService.maybe_update_summary(
                session, self.conversation_id, self.user_id
            )
            self.assertEqual(summary.summary, "Summary hiện tại")
        get_llm.assert_not_called()

    def test_builds_bounded_summary_context(self):
        current = ConversationSummary(
            conversation_id=self.conversation_id,
            summary="Đang đi Đà Nẵng.",
        )
        previous = ConversationSummary(
            conversation_id=self.conversation_id + 1,
            summary="Đã quan tâm Hội An.",
        )

        context = ConversationSummaryService.build_context_history(current, [previous])

        self.assertEqual(len(context), 2)
        self.assertIn("Đang đi Đà Nẵng.", context[0].content)
        self.assertIn("Đã quan tâm Hội An.", context[1].content)

    @patch("app.services.conversation_summary_service.get_chat_llm")
    def test_llm_failure_rolls_back_and_raises_controlled_error(self, get_llm):
        self._add_messages(8)
        get_llm.return_value.invoke.side_effect = TimeoutError()

        with Session(self.engine) as session:
            with self.assertRaises(ConversationSummaryError):
                ConversationSummaryService.maybe_update_summary(
                    session, self.conversation_id, self.user_id
                )

            self.assertIsNone(
                ConversationSummaryService.get_summary(
                    session, self.conversation_id, self.user_id
                )
            )

    @patch("app.services.conversation_summary_service.get_chat_llm")
    def test_does_not_read_another_users_summary(self, get_llm):
        self._add_messages(6)
        get_llm.return_value.invoke.return_value = Mock(content="Không được dùng")

        with Session(self.engine) as session:
            other = User(email=f"other-{id(self)}@example.com")
            session.add(other)
            session.commit()
            self.assertIsNone(
                ConversationSummaryService.get_summary(
                    session, self.conversation_id, other.id
                )
            )

            with self.assertRaises(ConversationSummaryError):
                ConversationSummaryService.maybe_update_summary(
                    session, self.conversation_id, other.id
                )
            get_llm.assert_not_called()
