"""
Integration and API tests for POST /rag/ask endpoint (Task 3.4).

Validates:
1. Validation errors on empty or whitespace queries (HTTP 422).
2. Existing /rag/search endpoint remains operational.
3. RAG /rag/ask API response for required queries:
   - "Chùa Linh Ứng có gì đặc biệt?"
   - "Chùa Linh Ứng nằm ở đâu?"
   - "Bà Nà Hills có gì?"
   - Một câu hỏi hoàn toàn không có trong knowledge.
4. Safe error handling (HTTP 503/500) without leaking secrets.
"""

import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from app.rag.chain import RAGChainError


class TestRAGAskAPI(unittest.TestCase):
    """Test suite for POST /rag/ask endpoint."""

    def setUp(self):
        self.client = TestClient(app)

    def test_search_endpoint_still_works(self):
        """Verify that existing /api/v1/rag/search is preserved and functioning."""
        res = self.client.post("/api/v1/rag/search", json={"query": "chùa linh ứng", "top_k": 2})
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["query"], "chùa linh ứng")
        self.assertIn("results", data)
        self.assertGreater(len(data["results"]), 0)

    def test_ask_validation_empty_query(self):
        """Empty query should trigger HTTP 422 validation error."""
        res = self.client.post("/api/v1/rag/ask", json={"query": ""})
        self.assertEqual(res.status_code, 422)

    def test_ask_validation_whitespace_query(self):
        """Whitespace-only query should trigger HTTP 422 validation error."""
        res = self.client.post("/api/v1/rag/ask", json={"query": "     "})
        self.assertEqual(res.status_code, 422)

    def test_ask_error_handling_sanitization(self):
        """RAG chain failure must return HTTP 503 without leaking secrets or traces."""
        with patch("app.api.routes.rag.get_rag_chain") as mock_chain_fn:
            mock_chain = MagicMock()
            mock_chain.invoke.side_effect = RAGChainError("Lỗi hệ thống nội bộ")
            mock_chain_fn.return_value = mock_chain

            res = self.client.post("/api/v1/rag/ask", json={"query": "Test câu hỏi"})
            self.assertEqual(res.status_code, 503)
            self.assertIn("không khả dụng", res.json()["detail"])

    def test_ask_chua_linh_ung_dac_biet(self):
        """Query 1: 'Chùa Linh Ứng có gì đặc biệt?'."""
        res = self.client.post(
            "/api/v1/rag/ask",
            json={"query": "Chùa Linh Ứng có gì đặc biệt?"},
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("conversation_id", data)
        self.assertIn("message", data)
        answer = data["message"]["content"]
        self.assertTrue(len(answer) > 20)

        answer_lower = answer.lower()
        has_facts = any(
            f in answer_lower
            for f in ["quan thế âm", "67m", "tượng phật", "sơn trà", "bán đảo"]
        )
        self.assertTrue(has_facts, f"Answer missing key facts: {answer}")

    def test_ask_chua_linh_ung_o_dau(self):
        """Query 2: 'Chùa Linh Ứng nằm ở đâu?'."""
        res = self.client.post(
            "/api/v1/rag/ask",
            json={"query": "Chùa Linh Ứng nằm ở đâu?"},
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("conversation_id", data)
        self.assertIn("message", data)
        answer = data["message"]["content"]

        answer_lower = answer.lower()
        has_location = any(
            loc in answer_lower
            for loc in ["sơn trà", "bãi bụt", "đà nẵng", "bán đảo"]
        )
        self.assertTrue(has_location, f"Answer missing location: {answer}")

    def test_ask_bana_hills(self):
        """Query 3: 'Bà Nà Hills có gì?'."""
        res = self.client.post(
            "/api/v1/rag/ask",
            json={"query": "Bà Nà Hills có gì?"},
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("conversation_id", data)
        self.assertIn("message", data)
        answer = data["message"]["content"]

        answer_lower = answer.lower()
        has_attraction = any(
            a in answer_lower
            for a in ["cáp treo", "cầu vàng", "golden bridge", "khu vui chơi"]
        )
        self.assertTrue(has_attraction, f"Answer missing Ba Na details: {answer}")

    def test_ask_unknown_query_no_hallucination(self):
        """Query 4: Out-of-knowledge question should decline to hallucinate."""
        res = self.client.post(
            "/api/v1/rag/ask",
            json={"query": "Vệ tinh nhân tạo Sputnik được phóng vào năm nào?"},
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("conversation_id", data)
        self.assertIn("message", data)
        answer = data["message"]["content"]

        answer_lower = answer.lower()
        has_decline = any(
            d in answer_lower
            for d in [
                "không tìm thấy đủ thông tin",
                "không có thông tin",
                "không có đủ thông tin",
                "chưa có thông tin",
            ]
        )
        self.assertTrue(has_decline, f"Answer should decline hallucinating: {answer}")


if __name__ == "__main__":
    unittest.main()
