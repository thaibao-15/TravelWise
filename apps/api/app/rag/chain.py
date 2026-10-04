"""
RAG Chain module for TravelWise.

Connects Retriever + Prompt + LLM into a complete retrieval-augmented generation workflow.
Supports Conversation Memory with Conversational Question Contextualization.
Reuses existing retriever, prompt template, and LLM factories.
Ensures no API keys, credentials, or internal secrets are leaked in logs or exceptions.
"""

import logging
from typing import Any, Dict, List, Optional, Sequence

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate

from app.rag.config import RAG_TOP_K
from app.rag.llm import extract_response_text, get_chat_llm
from app.rag.prompt import (
    format_docs,
    get_contextualize_prompt,
    get_rag_prompt,
    get_rag_prompt_with_history,
)
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
        prompt_with_history: Optional[ChatPromptTemplate] = None,
        contextualize_prompt: Optional[ChatPromptTemplate] = None,
        top_k: Optional[int] = None,
    ):
        self.retriever = retriever or RAGRetriever()
        self.llm = llm or get_chat_llm()
        self.prompt = prompt or get_rag_prompt()
        self.prompt_with_history = prompt_with_history or get_rag_prompt_with_history()
        self.contextualize_prompt = contextualize_prompt or get_contextualize_prompt()
        self.top_k = top_k or RAG_TOP_K

    def contextualize_question(
        self,
        question: str,
        chat_history: Optional[Sequence[Any]] = None,
    ) -> str:
        """Formulate a standalone question if chat history exists and references context.

        Args:
            question: Current user question (e.g. "Nó có gì đặc biệt?")
            chat_history: Sequence of previous messages (HumanMessage, AIMessage).

        Returns:
            Standalone rewritten question (e.g. "Chùa Linh Ứng có gì đặc biệt?")
        """
        clean_question = (question or "").strip()
        if not clean_question or not chat_history:
            return clean_question

        try:
            formatted_messages = self.contextualize_prompt.format_messages(
                chat_history=list(chat_history),
                question=clean_question,
            )
            response = self.llm.invoke(formatted_messages)
            rewritten = extract_response_text(getattr(response, "content", response)).strip()
            if rewritten:
                logger.info(
                    "Contextualized question: '%s' -> '%s'",
                    clean_question,
                    rewritten,
                )
                return rewritten
        except Exception as e:
            logger.warning(
                "Question contextualization failed, fallback to original query: %s",
                type(e).__name__,
            )

        return clean_question

    def invoke(
        self,
        question: str,
        standalone_question: Optional[str] = None,
        chat_history: Optional[Sequence[Any]] = None,
        top_k: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Execute the RAG pipeline for a given question and optional conversation context.

        Flow:
            1. Validate user question.
            2. Determine search query (standalone_question if provided, else clean_question).
            3. Retrieve top-K relevant documents from vector store.
            4. Build formatted context string.
            5. Fill prompt template (with history if provided).
            6. Invoke LLM and extract text response.

        Args:
            question: The raw user query string.
            standalone_question: Optional standalone rewritten question for retrieval.
            chat_history: Optional list of previous chat messages.
            top_k: Optional override for the number of documents to retrieve.

        Returns:
            Dict containing:
                - question (str): The cleaned input question.
                - standalone_question (str): The query used for retrieval.
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
                "standalone_question": "",
                "answer": "Vui lòng nhập câu hỏi để TravelWise có thể hỗ trợ bạn.",
                "sources": [],
            }

        k = top_k or self.top_k
        search_query = (standalone_question or clean_question).strip()

        # 2. Retrieve relevant documents using the standalone contextualized query
        try:
            retrieved_docs = self.retriever.search(query=search_query, top_k=k)
        except Exception as e:
            logger.error("RAG retrieval failed: %s", type(e).__name__)
            retrieved_docs = []

        # 3. Handle no relevant documents found
        if not retrieved_docs:
            return {
                "question": clean_question,
                "standalone_question": search_query,
                "answer": "Xin lỗi, hiện tại tôi không tìm thấy đủ thông tin về vấn đề này trong cơ sở dữ liệu để giải đáp cho bạn.",
                "sources": [],
            }

        # 4. Build context
        context_text = format_docs(retrieved_docs)

        # 5. Format prompt (use prompt_with_history if chat_history is provided)
        try:
            if chat_history:
                formatted_messages = self.prompt_with_history.format_messages(
                    context=context_text,
                    chat_history=list(chat_history),
                    question=clean_question,
                )
            else:
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
            "standalone_question": search_query,
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


def ask_rag(
    question: str,
    standalone_question: Optional[str] = None,
    chat_history: Optional[Sequence[Any]] = None,
    top_k: Optional[int] = None,
) -> Dict[str, Any]:
    """Convenience helper to ask a question through the RAG chain."""
    chain = get_rag_chain()
    return chain.invoke(
        question=question,
        standalone_question=standalone_question,
        chat_history=chat_history,
        top_k=top_k,
    )
