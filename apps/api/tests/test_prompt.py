"""
Unit tests for RAG Prompt Template module (Task 3.2).

Validates:
- Prompt template accepts both 'context' and 'question' input variables.
- Prompt generates the expected structure with system instructions and user context.
- Context content is fully preserved without truncation or data loss.
- format_docs utility correctly formats retrieved documents from multiple sources.
"""

import unittest

from langchain_core.documents import Document

from app.rag.prompt import (
    RAG_HUMAN_TEMPLATE,
    RAG_SYSTEM_INSTRUCTION,
    format_docs,
    get_rag_prompt,
    rag_chat_prompt,
    rag_string_prompt,
)
from app.schemas.rag import RAGSearchMetadata, RAGSearchResultItem


class TestRAGPrompt(unittest.TestCase):
    """Test suite for RAG Prompt construction and context preservation."""

    def setUp(self):
        self.sample_context = (
            "Chùa Linh Ứng nổi bật với tượng Quan Thế Âm cao 67m...\n\n"
            "---\n\n"
            "Giờ mở cửa: 7:00 - 18:00..."
        )
        self.sample_question = "Chùa Linh Ứng có gì đặc biệt?"

    def test_prompt_input_variables(self):
        """Prompt templates must accept 'context' and 'question' as required variables."""
        self.assertIn("context", rag_chat_prompt.input_variables)
        self.assertIn("question", rag_chat_prompt.input_variables)

        self.assertIn("context", rag_string_prompt.input_variables)
        self.assertIn("question", rag_string_prompt.input_variables)

    def test_prompt_structure_and_instructions(self):
        """Prompt must contain required instructions for grounded AI travel guide behavior."""
        # System instructions check
        self.assertIn("TravelWise", RAG_SYSTEM_INSTRUCTION)
        self.assertIn("Context", RAG_SYSTEM_INSTRUCTION)
        self.assertIn("tiếng Việt", RAG_SYSTEM_INSTRUCTION)
        self.assertIn("không tự bịa đặt", RAG_SYSTEM_INSTRUCTION.lower())

        # Human template check
        self.assertIn("## Context:", RAG_HUMAN_TEMPLATE)
        self.assertIn("Question:", RAG_HUMAN_TEMPLATE)

    def test_prompt_formatting_preserves_full_context_and_question(self):
        """Formatting the prompt must strictly preserve the entire context and question without loss."""
        messages = rag_chat_prompt.format_messages(
            context=self.sample_context,
            question=self.sample_question,
        )

        self.assertEqual(len(messages), 2)
        system_msg, human_msg = messages[0], messages[1]

        # System message verification
        self.assertIn("TravelWise", system_msg.content)

        # Human message verification — verify no content loss
        self.assertIn(self.sample_context, human_msg.content)
        self.assertIn(self.sample_question, human_msg.content)
        self.assertIn("Chùa Linh Ứng nổi bật với tượng Quan Thế Âm cao 67m...", human_msg.content)
        self.assertIn("Giờ mở cửa: 7:00 - 18:00...", human_msg.content)

    def test_get_rag_prompt_factory(self):
        """get_rag_prompt() factory returns a functional ChatPromptTemplate."""
        prompt = get_rag_prompt()
        self.assertEqual(prompt, rag_chat_prompt)

    def test_format_docs_from_langchain_documents(self):
        """format_docs should correctly concatenate LangChain Document page_content."""
        docs = [
            Document(page_content="Chùa Linh Ứng nổi bật với tượng Quan Thế Âm cao 67m."),
            Document(page_content="Giờ mở cửa: 7:00 - 18:00 hằng ngày."),
        ]
        result = format_docs(docs)

        self.assertIn("Chùa Linh Ứng nổi bật với tượng Quan Thế Âm cao 67m.", result)
        self.assertIn("Giờ mở cửa: 7:00 - 18:00 hằng ngày.", result)
        self.assertIn("\n\n---\n\n", result)

    def test_format_docs_from_retriever_search_dicts(self):
        """format_docs should handle dict results returned by RAGRetriever.search()."""
        search_results = [
            {
                "content": "Bà Nà Hills nằm ở độ cao 1487m so với mực nước biển.",
                "score": 0.89,
                "metadata": {"place_name": "Bà Nà Hills"},
            },
            {
                "content": "Cầu Vàng là biểu tượng du lịch nổi tiếng thế giới tại đây.",
                "score": 0.85,
                "metadata": {"place_name": "Cầu Vàng"},
            },
        ]
        result = format_docs(search_results)

        self.assertIn("Bà Nà Hills nằm ở độ cao 1487m so với mực nước biển.", result)
        self.assertIn("Cầu Vàng là biểu tượng du lịch nổi tiếng thế giới tại đây.", result)
        # Ensure scores and internal metadata are NOT dumped into user context text
        self.assertNotIn("0.89", result)
        self.assertNotIn("place_name", result)

    def test_format_docs_from_pydantic_schema_items(self):
        """format_docs should handle RAGSearchResultItem schemas from API response."""
        items = [
            RAGSearchResultItem(
                content="Cầu Rồng phun lửa và phun nước vào 21:00 thứ Bảy và Chủ Nhật.",
                score=0.92,
                metadata=RAGSearchMetadata(place_name="Cầu Rồng"),
            )
        ]
        result = format_docs(items)
        self.assertEqual(result, "Cầu Rồng phun lửa và phun nước vào 21:00 thứ Bảy và Chủ Nhật.")

    def test_format_docs_empty_fallback(self):
        """format_docs should provide fallback notice when input is empty."""
        self.assertEqual(format_docs([]), "Không có tài liệu liên quan.")
        self.assertEqual(format_docs(["", "   "]), "Không có tài liệu liên quan.")


if __name__ == "__main__":
    unittest.main()
