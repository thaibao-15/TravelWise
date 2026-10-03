"""
Unit and integration tests for RAG Chain module (Task 3.3).

Validates:
- Question validation and empty question handling.
- No relevant documents found fallback.
- LLM error handling and prevention of sensitive credential leakage.
- End-to-end RAG response for:
    1. "Chùa Linh Ứng có gì đặc biệt?"
    2. "Bà Nà Hills có gì?"
    3. Câu hỏi không có dữ liệu phù hợp ("Người ngoài hành tinh đang ở đâu?").
"""

import unittest
from unittest.mock import MagicMock, patch

from app.rag.chain import RAGChain, RAGChainError, ask_rag


class TestRAGChain(unittest.TestCase):
    """Test suite for RAG Chain execution and edge cases."""

    def test_empty_question_handling(self):
        """Empty or whitespace question should return user-friendly prompt without invoking LLM."""
        chain = RAGChain(
            retriever=MagicMock(),
            llm=MagicMock(),
        )

        res_empty = chain.invoke("")
        self.assertIn("Vui lòng nhập câu hỏi", res_empty["answer"])
        self.assertEqual(res_empty["sources"], [])

        res_whitespace = chain.invoke("   \n\t  ")
        self.assertIn("Vui lòng nhập câu hỏi", res_whitespace["answer"])

    def test_no_documents_found_fallback(self):
        """When retriever returns no documents, chain should return polite fallback."""
        mock_retriever = MagicMock()
        mock_retriever.search.return_value = []
        mock_llm = MagicMock()

        chain = RAGChain(
            retriever=mock_retriever,
            llm=mock_llm,
        )

        res = chain.invoke("Một địa điểm hoàn toàn không tồn tại")
        self.assertIn("không tìm thấy đủ thông tin", res["answer"].lower())
        self.assertEqual(res["sources"], [])
        mock_llm.invoke.assert_not_called()

    def test_llm_error_sanitization(self):
        """When LLM throws an exception containing credentials, chain must not expose secrets."""
        secret_leak = "AIzaSySecretLeakToken123456789"
        mock_retriever = MagicMock()
        mock_retriever.search.return_value = [
            {"content": "Một số nội dung mẫu", "score": 0.9, "metadata": {}}
        ]
        mock_llm = MagicMock()
        mock_llm.invoke.side_effect = Exception(f"Google API Error with auth token {secret_leak}")

        chain = RAGChain(
            retriever=mock_retriever,
            llm=mock_llm,
        )

        with self.assertRaises(RAGChainError) as ctx:
            chain.invoke("Câu hỏi bất kỳ")

        error_message = str(ctx.exception)
        self.assertNotIn(secret_leak, error_message)
        self.assertIn("lỗi", error_message.lower())

    def test_chua_linh_ung_query_e2e(self):
        """RAG chain should successfully answer 'Chùa Linh Ứng có gì đặc biệt?'."""
        res = ask_rag("Chùa Linh Ứng có gì đặc biệt?", top_k=2)

        self.assertIn("question", res)
        self.assertIn("answer", res)
        self.assertIn("sources", res)
        self.assertGreater(len(res["sources"]), 0)

        answer_lower = res["answer"].lower()
        # Should mention key facts from knowledge base (tượng Phật / Quan Thế Âm / 67m / Sơn Trà)
        has_expected_fact = any(
            k in answer_lower
            for k in ["quan thế âm", "67m", "tượng phật", "sơn trà", "bán đảo"]
        )
        self.assertTrue(
            has_expected_fact,
            f"Expected answer to contain Linh Ung details, got: {res['answer']}",
        )

    def test_bana_hills_query_e2e(self):
        """RAG chain should successfully answer 'Bà Nà Hills có gì?'."""
        res = ask_rag("Bà Nà Hills có gì?", top_k=2)

        self.assertIn("question", res)
        self.assertIn("answer", res)
        self.assertIn("sources", res)
        self.assertGreater(len(res["sources"]), 0)

        answer_lower = res["answer"].lower()
        # Should mention key facts from knowledge base (cáp treo / cầu vàng / golden bridge)
        has_expected_fact = any(
            k in answer_lower
            for k in ["cáp treo", "cầu vàng", "golden bridge", "khu vui chơi"]
        )
        self.assertTrue(
            has_expected_fact,
            f"Expected answer to contain Ba Na Hills details, got: {res['answer']}",
        )

    def test_unsupported_query_grounded_response(self):
        """RAG chain should decline to hallucinate on out-of-domain query ('Người ngoài hành tinh đang ở đâu?')."""
        res = ask_rag("Người ngoài hành tinh đang ở đâu?", top_k=2)

        self.assertIn("question", res)
        self.assertIn("answer", res)

        answer_lower = res["answer"].lower()
        # Must acknowledge lack of information per prompt rule 2
        has_decline_phrase = any(
            p in answer_lower
            for p in [
                "không tìm thấy đủ thông tin",
                "không có thông tin",
                "không có đủ thông tin",
                "chưa có thông tin",
            ]
        )
        self.assertTrue(
            has_decline_phrase,
            f"Expected answer to state lack of information, got: {res['answer']}",
        )


if __name__ == "__main__":
    unittest.main()
