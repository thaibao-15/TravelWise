"""
Unit tests for Chat Model connection (Task 3.1).
Tests both the LLM service factory and the FastAPI endpoint.
Uses unittest and unittest.mock to ensure zero additional test dependencies.
"""

import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app
from app.rag.llm import extract_response_text, get_chat_llm


class TestLLMConnection(unittest.TestCase):
    """Test suite for LLM initialization and FastAPI /rag/test-llm endpoint."""

    def setUp(self):
        self.client = TestClient(app)

    def test_extract_response_text_handles_str_and_list(self):
        """extract_response_text must handle both plain strings and Gemini block lists."""
        self.assertEqual(extract_response_text("Hello world"), "Hello world")
        gemini_blocks = [{"type": "text", "text": "Hello "}, {"type": "text", "text": "Gemini"}]
        self.assertEqual(extract_response_text(gemini_blocks), "Hello Gemini")

    def test_get_chat_llm_raises_when_no_api_key(self):
        """get_chat_llm must raise ValueError when provider key is not set."""
        with patch("app.rag.llm.GEMINI_API_KEY", None):
            with patch("app.rag.llm.LLM_PROVIDER", "gemini"):
                with self.assertRaises(ValueError) as ctx:
                    get_chat_llm(provider="gemini")
                self.assertIn("GEMINI_API_KEY is not configured", str(ctx.exception))

    def test_get_chat_llm_gemini_initialization(self):
        """get_chat_llm must instantiate ChatGoogleGenerativeAI with settings."""
        mock_key = "AIzaSyTestMockKey"
        with patch("app.rag.llm.GEMINI_API_KEY", mock_key):
            with patch("app.rag.llm.LLM_PROVIDER", "gemini"):
                with patch("langchain_google_genai.ChatGoogleGenerativeAI") as mock_gemini:
                    get_chat_llm(provider="gemini")
                    mock_gemini.assert_called_once_with(
                        model=settings.GEMINI_MODEL,
                        google_api_key=mock_key,
                        temperature=0.7,
                    )

    def test_get_chat_llm_openai_initialization(self):
        """get_chat_llm must instantiate ChatOpenAI when provider is openai."""
        mock_key = "sk-test-mock-key-12345"
        with patch("app.rag.llm.OPENAI_API_KEY", mock_key):
            with patch("app.rag.llm.LLM_PROVIDER", "openai"):
                with patch("langchain_openai.ChatOpenAI") as mock_chat_openai:
                    get_chat_llm(provider="openai")
                    expected_kwargs = {
                        "model": settings.OPENAI_MODEL,
                        "api_key": mock_key,
                        "temperature": 0.7,
                    }
                    if settings.OPENAI_BASE_URL:
                        expected_kwargs["base_url"] = settings.OPENAI_BASE_URL
                    mock_chat_openai.assert_called_once_with(**expected_kwargs)

    def test_fastapi_test_llm_endpoint_success(self):
        """FastAPI /rag/test-llm should call LLM and return 200 with response content."""
        fake_llm = MagicMock()
        mock_response = MagicMock()
        mock_response.content = "Xin chào! Tôi là trợ lý du lịch TravelWise."
        fake_llm.invoke.return_value = mock_response

        with patch("app.api.routes.rag.get_chat_llm", return_value=fake_llm):
            res = self.client.post(
                "/rag/test-llm",
                json={"prompt": "Xin chào"},
            )
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertEqual(data["status"], "success")
            self.assertEqual(data["provider"], settings.LLM_PROVIDER)
            self.assertEqual(data["response"], "Xin chào! Tôi là trợ lý du lịch TravelWise.")
            fake_llm.invoke.assert_called_once_with("Xin chào")

    def test_fastapi_test_llm_endpoint_no_key_error(self):
        """FastAPI /rag/test-llm should handle missing API key cleanly without leaking info."""
        with patch("app.api.routes.rag.get_chat_llm", side_effect=ValueError("API key missing")):
            res = self.client.post(
                "/rag/test-llm",
                json={"prompt": "Xin chào"},
            )
            self.assertEqual(res.status_code, 500)
            data = res.json()
            self.assertIn("API key missing", data["detail"])
            self.assertNotIn("sk-", res.text)
            self.assertNotIn("AIza", res.text)

    def test_fastapi_test_llm_endpoint_api_exception(self):
        """FastAPI /rag/test-llm should safely handle API exceptions without leaking keys."""
        secret_key_leak = "AIzaSy-live-secret-never-expose"
        with patch(
            "app.api.routes.rag.get_chat_llm",
            side_effect=Exception(f"LLM error with key {secret_key_leak}"),
        ):
            res = self.client.post(
                "/rag/test-llm",
                json={"prompt": "Xin chào"},
            )
            self.assertEqual(res.status_code, 502)
            # Crucial: the error response must NOT contain the secret key or raw exception string
            self.assertNotIn(secret_key_leak, res.text)
            self.assertEqual(res.json()["detail"], "Failed to communicate with LLM service.")


if __name__ == "__main__":
    unittest.main()
