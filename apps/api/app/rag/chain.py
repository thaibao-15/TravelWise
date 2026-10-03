"""
RAG Chain module for TravelWise.

Connects Retriever + Prompt + LLM into a complete retrieval-augmented generation workflow.
Reuses existing retriever, prompt template, and LLM factories.
Ensures no API keys, credentials, or internal secrets are leaked in logs or exceptions.
"""

import logging
from typing import Any, Dict, List, Optional

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate

from app.rag.config import RAG_TOP_K
from app.rag.llm import extract_response_text, get_chat_llm
from app.rag.prompt import format_docs, get_rag_prompt
from app.rag.retriever import RAGRetriever

logger = logging.getLogger(__name__)


class RAGChainError(Exception):
    """Custom exception raised when RAG chain execution fails without leaking sensitive data."""

    def __init__(self, message: str = "Đã xảy ra lỗi trong quá trình xử lý câu hỏi. Vui lòng thử lại sau."):
        super().__init__(message)
        self.message = message


class RAGChain:
    """End-to-end RAG Chain combining Retrieval, Context Construction, Prompting, and LLM generation."""

    def __init__(
        self,
        retriever: Optional[RAGRetriever] = None,
        llm: Optional[BaseChatModel] = None,
        prompt: Optional[ChatPromptTemplate] = None,
        top_k: Optional[int] = None,
    ):
        self.retriever = retriever or RAGRetriever()
        self.llm = llm or get_chat_llm()
        self.prompt = prompt or get_rag_prompt()
        self.top_k = top_k or RAG_TOP_K

    def invoke(
        self,
        question: str,
        top_k: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Execute the RAG pipeline for a given question.

        Flow:
            1. Validate user question.
            2. Retrieve top-K relevant documents from vector store.
            3. Build formatted context string.
            4. Fill prompt template.
            5. Invoke LLM and extract text response.

        Args:
            question: The user query string.
            top_k: Optional override for the number of documents to retrieve.

        Returns:
            Dict containing:
                - question (str): The cleaned input question.
                - answer (str): Generated answer from LLM or fallback message.
                - sources (list): List of retrieved source document dictionaries for debugging.

        Raises:
            RAGChainError: If LLM call or processing fails (sanitized, zero secret leakage).
        """
        clean_question = (question or "").strip()

        # 1. Handle empty question edge case
        if not clean_question:
            return {
                "question": "",
                "answer": "Vui lòng nhập câu hỏi để TravelWise có thể hỗ trợ bạn.",
                "sources": [],
            }

        k = top_k or self.top_k

        # 2. Retrieve relevant documents
        try:
            retrieved_docs = self.retriever.search(query=clean_question, top_k=k)
        except Exception as e:
            logger.error("RAG retrieval failed: %s", type(e).__name__)
            retrieved_docs = []

        # 3. Handle no relevant documents found
        if not retrieved_docs:
            return {
                "question": clean_question,
                "answer": "Xin lỗi, hiện tại tôi không tìm thấy đủ thông tin về vấn đề này trong cơ sở dữ liệu để giải đáp cho bạn.",
                "sources": [],
            }

        # 4. Build context
        context_text = format_docs(retrieved_docs)

        # 5. Format prompt
        try:
            formatted_messages = self.prompt.format_messages(
                context=context_text,
                question=clean_question,
            )
        except Exception as e:
            logger.error("RAG prompt formatting error: %s", type(e).__name__)
            raise RAGChainError("Lỗi định dạng câu hỏi và ngữ cảnh.") from None

        # 6. Invoke LLM
        try:
            llm_response = self.llm.invoke(formatted_messages)
            answer = extract_response_text(getattr(llm_response, "content", llm_response)).strip()
        except Exception as e:
            logger.error("RAG LLM execution failed: %s", type(e).__name__)
            raise RAGChainError("Đã xảy ra lỗi khi kết nối với mô hình AI. Vui lòng thử lại sau.") from None

        return {
            "question": clean_question,
            "answer": answer,
            "sources": retrieved_docs,
        }


_rag_chain_instance: Optional[RAGChain] = None


def get_rag_chain() -> RAGChain:
    """Factory function returning a shared or newly initialized RAGChain instance."""
    global _rag_chain_instance
    if _rag_chain_instance is None:
        _rag_chain_instance = RAGChain()
    return _rag_chain_instance


def ask_rag(question: str, top_k: Optional[int] = None) -> Dict[str, Any]:
    """Convenience helper to ask a question through the RAG chain."""
    chain = get_rag_chain()
    return chain.invoke(question=question, top_k=top_k)
