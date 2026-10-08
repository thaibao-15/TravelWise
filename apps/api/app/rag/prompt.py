"""
RAG Prompt Template module for TravelWise.

Defines prompt templates and context formatting utilities for combining
retrieved knowledge chunks with user queries.
"""

from typing import Any, Sequence, Union

from langchain_core.prompts import (
    ChatPromptTemplate,
    HumanMessagePromptTemplate,
    MessagesPlaceholder,
    PromptTemplate,
    SystemMessagePromptTemplate,
)

# -----------------------------------------------------------------------------
# System Prompt Instructions
# -----------------------------------------------------------------------------
RAG_SYSTEM_INSTRUCTION = (
    "Bạn là trợ lý AI Travel Guide thông minh, thân thiện và đáng tin cậy của ứng dụng TravelWise.\n"
    "Nhiệm vụ của bạn là giải đáp câu hỏi và hỗ trợ du khách dựa trên phần Context được cung cấp và lịch sử cuộc trò chuyện.\n\n"
    "Quy tắc bắt buộc:\n"
    "1. Chỉ sử dụng thông tin có trong phần Context để trả lời. Tuyệt đối không tự bịa đặt hoặc suy diễn thông tin nằm ngoài Context.\n"
    "2. Nếu phần Context không có đủ thông tin để trả lời câu hỏi, hãy nói rõ rằng bạn không tìm thấy đủ thông tin trong hệ thống để trả lời.\n"
    "3. Trả lời bằng tiếng Việt nếu câu hỏi bằng tiếng Việt. Văn phong tự nhiên, ngắn gọn, lịch sự và phù hợp với vai trò hướng dẫn viên du lịch.\n"
    "4. Không đề cập đến các chi tiết kỹ thuật nội bộ như điểm số liên quan (score), chunk index hoặc metadata nếu không cần thiết cho người dùng."
)

# -----------------------------------------------------------------------------
# Contextualize Question Instruction (Conversational Query Rewriting)
# -----------------------------------------------------------------------------
CONTEXTUALIZE_Q_SYSTEM_INSTRUCTION = (
    "Dựa vào lịch sử trò chuyện và câu hỏi mới nhất của người dùng (câu hỏi có thể chứa đại từ "
    "như 'nó', 'ở đó', 'chỗ này', 'giá bao nhiêu', 'đi như thế nào'...), hãy viết lại câu hỏi "
    "thành một câu hỏi độc lập, đầy đủ ngữ cảnh để có thể tìm kiếm thông tin mà không cần xem lại lịch sử trò chuyện.\n"
    "Quy tắc bắt buộc:\n"
    "1. KHÔNG trả lời câu hỏi, CHỈ viết lại câu hỏi.\n"
    "2. Nếu câu hỏi đã độc lập hoặc là chủ đề mới, hãy giữ nguyên câu hỏi gốc.\n"
    "3. Chỉ trả về duy nhất câu hỏi đã viết lại, không thêm bất kỳ lời dẫn hay giải thích nào."
)

# -----------------------------------------------------------------------------
# Contextualize ChatPromptTemplate
# -----------------------------------------------------------------------------
contextualize_q_prompt: ChatPromptTemplate = ChatPromptTemplate.from_messages(
    [
        SystemMessagePromptTemplate.from_template(CONTEXTUALIZE_Q_SYSTEM_INSTRUCTION),
        MessagesPlaceholder(variable_name="chat_history"),
        HumanMessagePromptTemplate.from_template("{question}"),
    ]
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
# Standard ChatPromptTemplate (for Chat models without history)
# -----------------------------------------------------------------------------
rag_chat_prompt: ChatPromptTemplate = ChatPromptTemplate.from_messages(
    [
        SystemMessagePromptTemplate.from_template(RAG_SYSTEM_INSTRUCTION),
        HumanMessagePromptTemplate.from_template(RAG_HUMAN_TEMPLATE),
    ]
)

# -----------------------------------------------------------------------------
# ChatPromptTemplate with History (Conversation Memory)
# -----------------------------------------------------------------------------
rag_chat_prompt_with_history: ChatPromptTemplate = ChatPromptTemplate.from_messages(
    [
        SystemMessagePromptTemplate.from_template(RAG_SYSTEM_INSTRUCTION),
        MessagesPlaceholder(variable_name="chat_history"),
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


def get_rag_prompt_with_history() -> ChatPromptTemplate:
    """Returns the ChatPromptTemplate for RAG with conversation history."""
    return rag_chat_prompt_with_history


def get_contextualize_prompt() -> ChatPromptTemplate:
    """Returns the ChatPromptTemplate for question contextualization."""
    return contextualize_q_prompt


# -----------------------------------------------------------------------------
# Voice Conversation Specific Prompt (Ultra-low latency, spoken conversational)
# -----------------------------------------------------------------------------
RAG_VOICE_SYSTEM_INSTRUCTION = (
    "Bạn là trợ lý AI TravelWise đang nói chuyện trực tiếp bằng giọng nói (Voice Call) với du khách.\n"
    "Nhiệm vụ: Trả lời câu hỏi dựa trên Context và lịch sử trò chuyện.\n\n"
    "Quy tắc bắt buộc cho đàm thoại giọng nói:\n"
    "1. Trả lời súc tích, tự nhiên như giao tiếp nói chuyện thông thường: chỉ từ 2 đến 3 câu ngắn (tối đa 40-60 từ).\n"
    "2. Đi thẳng vào câu trả lời, không chào hỏi rườm rà ở mỗi lượt nói.\n"
    "3. TUYỆT ĐỐI KHÔNG dùng định dạng markdown (không **, ###, gạch đầu dòng -, số thứ tự 1. 2., emoji hay link). Chỉ dùng câu chữ văn xuôi thuần túy để máy đọc mượt mà.\n"
    "4. Nếu không có thông tin, hãy trả lời ngắn gọn: 'Hiện tại tôi chưa có thông tin về địa điểm này, bạn có muốn hỏi về nơi khác không?'."
)

rag_voice_prompt: ChatPromptTemplate = ChatPromptTemplate.from_messages(
    [
        SystemMessagePromptTemplate.from_template(RAG_VOICE_SYSTEM_INSTRUCTION),
        HumanMessagePromptTemplate.from_template(RAG_HUMAN_TEMPLATE),
    ]
)

rag_voice_prompt_with_history: ChatPromptTemplate = ChatPromptTemplate.from_messages(
    [
        SystemMessagePromptTemplate.from_template(RAG_VOICE_SYSTEM_INSTRUCTION),
        MessagesPlaceholder(variable_name="chat_history"),
        HumanMessagePromptTemplate.from_template(RAG_HUMAN_TEMPLATE),
    ]
)


def get_rag_voice_prompt() -> ChatPromptTemplate:
    """Returns ChatPromptTemplate tailored for low-latency voice mode."""
    return rag_voice_prompt


def get_rag_voice_prompt_with_history() -> ChatPromptTemplate:
    """Returns ChatPromptTemplate with history tailored for low-latency voice mode."""
    return rag_voice_prompt_with_history



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
