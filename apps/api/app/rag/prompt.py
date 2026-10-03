"""
RAG Prompt Template module for TravelWise.

Defines prompt templates and context formatting utilities for combining
retrieved knowledge chunks with user queries.
"""

from typing import Any, Sequence, Union

from langchain_core.prompts import (
    ChatPromptTemplate,
    HumanMessagePromptTemplate,
    PromptTemplate,
    SystemMessagePromptTemplate,
)

# -----------------------------------------------------------------------------
# System Prompt Instructions
# -----------------------------------------------------------------------------
RAG_SYSTEM_INSTRUCTION = (
    "Bạn là trợ lý AI Travel Guide thông minh, thân thiện và đáng tin cậy của ứng dụng TravelWise.\n"
    "Nhiệm vụ của bạn là giải đáp câu hỏi và hỗ trợ du khách dựa trên phần Context được cung cấp.\n\n"
    "Quy tắc bắt buộc:\n"
    "1. Chỉ sử dụng thông tin có trong phần Context để trả lời. Tuyệt đối không tự bịa đặt hoặc suy diễn thông tin nằm ngoài Context.\n"
    "2. Nếu phần Context không có đủ thông tin để trả lời câu hỏi, hãy nói rõ rằng bạn không tìm thấy đủ thông tin trong hệ thống để trả lời.\n"
    "3. Trả lời bằng tiếng Việt nếu câu hỏi bằng tiếng Việt. Văn phong tự nhiên, ngắn gọn, lịch sự và phù hợp với vai trò hướng dẫn viên du lịch.\n"
    "4. Không đề cập đến các chi tiết kỹ thuật nội bộ như điểm số liên quan (score), chunk index hoặc metadata nếu không cần thiết cho người dùng."
)

# -----------------------------------------------------------------------------
# Human / User Template
# -----------------------------------------------------------------------------
RAG_HUMAN_TEMPLATE = (
    "## Context:\n"
    "{context}\n\n"
    "Question:\n"
    "{question}"
)

# -----------------------------------------------------------------------------
# Standard ChatPromptTemplate (for Chat models: Gemini, OpenAI, etc.)
# -----------------------------------------------------------------------------
rag_chat_prompt: ChatPromptTemplate = ChatPromptTemplate.from_messages(
    [
        SystemMessagePromptTemplate.from_template(RAG_SYSTEM_INSTRUCTION),
        HumanMessagePromptTemplate.from_template(RAG_HUMAN_TEMPLATE),
    ]
)

# -----------------------------------------------------------------------------
# Standard String PromptTemplate
# -----------------------------------------------------------------------------
RAG_FULL_TEMPLATE = (
    f"{RAG_SYSTEM_INSTRUCTION}\n\n"
    f"{RAG_HUMAN_TEMPLATE}"
)

rag_string_prompt: PromptTemplate = PromptTemplate(
    input_variables=["context", "question"],
    template=RAG_FULL_TEMPLATE,
)


def get_rag_prompt() -> ChatPromptTemplate:
    """Returns the default ChatPromptTemplate for RAG chains."""
    return rag_chat_prompt


def format_docs(docs: Sequence[Any]) -> str:
    """Format retrieved documents or search result items into a clean context string.

    Supports:
        - LangChain Document objects (doc.page_content)
        - Dict objects with 'content' key (e.g. from RAGRetriever.search)
        - Pydantic models with 'content' attribute (e.g. RAGSearchResultItem)
        - Plain strings

    Args:
        docs: A sequence of document-like objects.

    Returns:
        Clean concatenated string with separators, or an empty string notice if empty.
    """
    if not docs:
        return "Không có tài liệu liên quan."

    extracted_texts: list[str] = []
    for doc in docs:
        text = ""
        if isinstance(doc, str):
            text = doc.strip()
        elif hasattr(doc, "page_content"):
            text = str(getattr(doc, "page_content", "")).strip()
        elif isinstance(doc, dict):
            text = str(doc.get("content", "")).strip()
        elif hasattr(doc, "content"):
            text = str(getattr(doc, "content", "")).strip()
        else:
            text = str(doc).strip()

        if text:
            extracted_texts.append(text)

    if not extracted_texts:
        return "Không có tài liệu liên quan."

    return "\n\n---\n\n".join(extracted_texts)
