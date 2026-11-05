"""Tests for Gemini/RAG integration into LiveKit Voice Agent."""

import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from agent import extract_conversation_id, extract_user_id
from services.rag_client import RAGClientError, TravelWiseRAGClient


class TestRAGMetadataExtraction(unittest.TestCase):
    """Test parsing conversation_id and user_id from room and participant metadata."""

    def test_extract_conversation_id_from_metadata(self):
        conv_id = extract_conversation_id("random_room", '{"conversation_id": 42, "user_id": 7}')
        self.assertEqual(conv_id, 42)

    def test_extract_conversation_id_from_room_name(self):
        conv_id = extract_conversation_id("travelwise_conv_88", None)
        self.assertEqual(conv_id, 88)

    def test_extract_conversation_id_fallback_none(self):
        conv_id = extract_conversation_id("custom_room_name", None)
        self.assertIsNone(conv_id)

    def test_extract_user_id_from_metadata(self):
        mock_participant = MagicMock()
        mock_participant.metadata = '{"user_id": 99, "conversation_id": 12}'
        mock_participant.identity = "user_99"
        user_id = extract_user_id(mock_participant)
        self.assertEqual(user_id, 99)

    def test_extract_user_id_from_identity(self):
        mock_participant = MagicMock()
        mock_participant.metadata = ""
        mock_participant.identity = "user_105"
        user_id = extract_user_id(mock_participant)
        self.assertEqual(user_id, 105)

    def test_extract_user_id_fallback_none(self):
        mock_participant = MagicMock()
        mock_participant.metadata = ""
        mock_participant.identity = "guest_participant"
        user_id = extract_user_id(mock_participant)
        self.assertIsNone(user_id)


class TestRAGClientUnit(unittest.IsolatedAsyncioTestCase):
    """Unit tests for TravelWiseRAGClient."""

    def setUp(self):
        self.client = TravelWiseRAGClient(
            base_url="http://127.0.0.1:8000",
            jwt_secret="test-secret-key-12345",
            jwt_algorithm="HS256",
        )

    def test_token_generation(self):
        token = self.client.generate_auth_token(user_id=15)
        self.assertIsInstance(token, str)
        self.assertTrue(len(token) > 50)

    @patch("httpx.AsyncClient.post")
    async def test_ask_success_payload_and_headers(self, mock_post):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "conversation_id": 25,
            "message": {
                "id": 101,
                "content": "Cầu Rồng Đà Nẵng phun lửa lúc 21h thứ Bảy và Chủ nhật.",
            },
            "planning_context": None,
        }
        mock_post.return_value = mock_response

        res = await self.client.ask(
            question="Cầu Rồng phun lửa lúc mấy giờ?",
            conversation_id=25,
            user_id=7,
            mode="voice",
        )

        self.assertEqual(res["answer"], "Cầu Rồng Đà Nẵng phun lửa lúc 21h thứ Bảy và Chủ nhật.")
        self.assertEqual(res["conversation_id"], 25)
        self.assertEqual(res["message_id"], 101)
        self.assertGreaterEqual(res["duration_ms"], 0.0)

        # Check call arguments
        mock_post.assert_called_once()
        call_kwargs = mock_post.call_args[1]
        self.assertEqual(call_kwargs["json"]["query"], "Cầu Rồng phun lửa lúc mấy giờ?")
        self.assertEqual(call_kwargs["json"]["mode"], "voice")
        self.assertIn("Authorization", call_kwargs["headers"])
        self.assertTrue(call_kwargs["headers"]["Authorization"].startswith("Bearer "))

    @patch("httpx.AsyncClient.post")
    async def test_ask_error_handling(self, mock_post):
        mock_response = MagicMock()
        mock_response.status_code = 503
        mock_response.text = "Service Unavailable"
        mock_post.return_value = mock_response

        with self.assertRaises(RAGClientError) as ctx:
            await self.client.ask(
                question="Thời tiết Đà Nẵng thế nào?",
                conversation_id=1,
            )
        self.assertEqual(ctx.exception.status_code, 503)


class TestRAGLiveBackendQueries(unittest.IsolatedAsyncioTestCase):
    """Live verification against the active TravelWise FastAPI backend."""

    async def asyncSetUp(self):
        self.client = TravelWiseRAGClient()

    async def test_live_rag_known_location_query(self):
        """Test question about a known location in TravelWise knowledge base (Cầu Rồng / Bán đảo Sơn Trà)."""
        res = await self.client.ask(
            question="Cầu Rồng Đà Nẵng có gì độc đáo và trình diễn phun lửa khi nào?",
            mode="voice",
        )
        self.assertIn("Cầu Rồng", res["answer"])
        self.assertIn("phun lửa", res["answer"].lower())
        self.assertIsNotNone(res["conversation_id"])

    async def test_live_rag_follow_up_with_context(self):
        """Test follow-up question referencing context from previous question using pronoun 'nó'."""
        # 1. Ask initial question to establish conversation
        initial_res = await self.client.ask(
            question="Chùa Linh Ứng ở Bán đảo Sơn Trà có tượng Phật Bà không?",
            mode="voice",
        )
        conv_id = initial_res["conversation_id"]
        self.assertIsNotNone(conv_id)
        self.assertTrue(len(initial_res["answer"]) > 20)

        # 2. Ask follow-up question using pronoun 'nó' and 'ở đó'
        follow_up_res = await self.client.ask(
            question="Nó cao bao nhiêu mét và đứng ở đó nhìn thấy gì?",
            conversation_id=conv_id,
            mode="voice",
        )
        # Verify it answered about the Buddha statue / Linh Ung pagoda height & view
        answer_lower = follow_up_res["answer"].lower()
        self.assertEqual(follow_up_res["conversation_id"], conv_id)
        self.assertTrue(
            "mét" in answer_lower or "tượng" in answer_lower or "biển" in answer_lower or "sơn trà" in answer_lower or "đà nẵng" in answer_lower,
            f"Follow-up answer did not maintain context: {follow_up_res['answer']}",
        )


if __name__ == "__main__":
    unittest.main()
