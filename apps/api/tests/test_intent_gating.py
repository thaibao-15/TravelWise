"""
Tests for Query Intent Gating (should_retrieve_knowledge).
"""

import unittest
from langchain_core.messages import AIMessage, HumanMessage

from app.rag.chain import should_retrieve_knowledge


class TestQueryIntentGating(unittest.TestCase):
    """Verify that chitchat and short checklist queries bypass vector DB retrieval."""

    def test_chitchat_greetings_bypass_retrieval(self):
        greetings = [
            "Chào bạn",
            "Xin chào",
            "Hi Linh",
            "Hello",
            "Alo",
            "Bạn ơi",
            "Bạn là ai?",
            "Tên bạn là gì",
        ]
        for q in greetings:
            with self.subTest(query=q):
                self.assertFalse(
                    should_retrieve_knowledge(q),
                    f"Query '{q}' should bypass retrieval",
                )

    def test_chitchat_thanks_and_compliments_bypass_retrieval(self):
        phrases = [
            "Cảm ơn bạn nhé",
            "Thanks!",
            "Thank you",
            "Tạm biệt",
            "Bye",
            "Ok bạn",
            "Tuyệt vời quá",
            "Được rồi",
            "Bạn khỏe không?",
        ]
        for q in phrases:
            with self.subTest(query=q):
                self.assertFalse(
                    should_retrieve_knowledge(q),
                    f"Query '{q}' should bypass retrieval",
                )

    def test_short_checklist_criteria_bypass_retrieval(self):
        checklist_answers = [
            "2 người",
            "3 người lớn",
            "ngày mai",
            "cuối tuần này",
            "3 ngày 2 đêm",
            "5 triệu",
            "khoảng 10 triệu",
            "đi máy bay",
            "khách sạn 4 sao",
        ]
        for q in checklist_answers:
            with self.subTest(query=q):
                self.assertFalse(
                    should_retrieve_knowledge(q),
                    f"Query '{q}' should bypass retrieval",
                )

    def test_generic_planning_requests_without_entity_bypass_retrieval(self):
        generic_queries = [
            "Lên kế hoạch giúp mình",
            "Tạo lịch trình du lịch",
            "Tư vấn lịch trình",
            "Gợi ý chuyến đi",
        ]
        for q in generic_queries:
            with self.subTest(query=q):
                self.assertFalse(
                    should_retrieve_knowledge(q),
                    f"Query '{q}' should bypass retrieval without entities",
                )

    def test_place_and_landmark_queries_require_retrieval(self):
        place_queries = [
            "Chùa Linh Ứng ở đâu?",
            "Giá vé Bà Nà Hills bao nhiêu?",
            "Đà Nẵng có gì chơi?",
            "Đèo Hải Vân cách trung tâm bao xa?",
            "Cầu Rồng mấy giờ phun lửa?",
            "Phố cổ Hội An có gì ăn ngon?",
            "Bán đảo Sơn Trà",
        ]
        for q in place_queries:
            with self.subTest(query=q):
                self.assertTrue(
                    should_retrieve_knowledge(q),
                    f"Query '{q}' should trigger retrieval",
                )

    def test_contextual_inquiry_with_history_triggers_retrieval(self):
        chat_history = [
            HumanMessage(content="Chùa Linh Ứng có đẹp không?"),
            AIMessage(content="Chùa Linh Ứng rất đẹp và nổi tiếng tại Đà Nẵng."),
        ]
        # Follow-up question has inquiry keyword "ở đâu" and history has "Chùa Linh Ứng"
        self.assertTrue(
            should_retrieve_knowledge("Nó ở đâu?", chat_history=chat_history)
        )
        self.assertTrue(
            should_retrieve_knowledge("Giá vé bao nhiêu?", chat_history=chat_history)
        )


if __name__ == "__main__":
    unittest.main()

