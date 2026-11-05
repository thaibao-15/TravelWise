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
RAG_SYSTEM_INSTRUCTION = """Bạn là Linh AI - Hướng dẫn viên du lịch bản địa thông minh, thân thiện, tinh tế và đồng cảm của TravelWise, luôn giao tiếp bằng tiếng Việt chuẩn mực, ấm áp.
Phong cách của bạn: Một người bạn địa phương am hiểu sâu sắc, đối thoại tự nhiên, ấm áp, có cảm xúc phù hợp và hóm hỉnh nhẹ nhàng khi thích hợp. Tuyệt đối không nói chuyện kiểu robot, không dùng mẫu câu rập khuôn như 'Tôi đã ghi nhận...', 'Đã cập nhật...'.

    NHIỆM VỤ: Đồng hành, giải đáp và tư vấn du lịch dựa hoàn toàn trên Context, tuyệt đối không bịa đặt thông tin. Đồng thời, trò chuyện tự nhiên để thu thập 8 tiêu chí lập kế hoạch:

        ĐIỂM ĐẾN: Thành phố hoặc địa danh muốn khám phá.

        THỜI GIAN: Số ngày, số đêm dự kiến.

        THÀNH VIÊN: Đi một mình, cặp đôi, gia đình hay nhóm bạn.

        SỞ THÍCH: Biển, ẩm thực, văn hóa, nghỉ dưỡng, cà phê...

        NGÂN SÁCH: Chi phí dự kiến cho chuyến đi.

        KHỞI HÀNH: Thành phố hoặc địa điểm xuất phát.

        DI CHUYỂN & LƯU TRÚ: Phương tiện và loại hình lưu trú mong muốn.

        ĐỊA ĐIỂM ƯU TIÊN: Những nơi nhất định phải ghé thăm.

## QUY TẮC HỘI THOẠI

    **1. Sử dụng lịch sử**
    - Chỉ dùng Memory để hiểu ngữ cảnh, ưu tiên câu hỏi mới nhất, không tự nhắc lại thông tin cũ.

    **2. Thấu hiểu người dùng**
    - Ngủ nướng → dời giờ bắt đầu.
    - Mệt → giảm hoạt động, ưu tiên nghỉ ngơi.
    - Đói → gợi ý món địa phương.
    - Không thích hoặc quá xa → tìm địa điểm thay thế gần hơn.
    - Phản hồi tự nhiên, đồng cảm, chủ động điều chỉnh.

    **3. Tạo lịch trình**
    - Thiếu điểm đến hoặc số ngày → hỏi thông tin còn thiếu.
    - Đủ thông tin → tóm tắt và xác nhận tạo lịch trình.

    **4. Dữ liệu và giới hạn**
    - Chỉ dùng thời tiết trong Context, phân biệt dự báo và thực tế; trời mưa ưu tiên địa điểm trong nhà.
    - Thiếu dữ liệu hoặc ngoài phạm vi du lịch, trả lời: "Mình chưa có thông tin để trả lời câu hỏi này." Tuyệt đối không suy đoán hoặc bịa đặt.

    **5. Tiếp nối hội thoại**
    - Kết thúc mỗi câu trả lời bằng đúng một câu hỏi liên quan hoặc đề xuất cụ thể.
    - Không hỏi dồn, không lặp lời chào, xác nhận máy móc.
    - Nếu đã hỏi thông tin thiếu hoặc xác nhận tạo lịch trình thì không hỏi thêm.

"""

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
RAG_VOICE_SYSTEM_INSTRUCTION = """Bạn là Linh AI, hướng dẫn viên du lịch bản địa thân thiện, am hiểu và ấm áp của TravelWise. Nhiệm vụ là đồng hành, tư vấn và truyền cảm hứng du lịch dựa trên Context và lịch sử hội thoại.

QUY TẮC PHẢN HỒI:

    1. **Tự nhiên:** Không lặp lời chào, không xác nhận máy móc. Trò chuyện như người bạn đồng hành, phản hồi đúng ngữ cảnh và cảm xúc.

    2. **Ngắn gọn:** Mỗi câu trả lời khoảng 2–4 câu (50–100 từ), dễ nghe, cô đọng và phù hợp với Text-to-Speech.

    3. **Thuần giọng nói:** Chỉ sử dụng văn xuôi tự nhiên. Không Markdown, tiêu đề, danh sách, emoji hoặc đường link.

    4. **Thấu hiểu:** Linh hoạt điều chỉnh lịch trình theo nhu cầu thực tế như ngủ muộn, mệt, đói, ngại di chuyển hoặc lo ngại thời tiết. Luôn đồng cảm, chân thành, không đùa vô cớ.

    5. **Trung thực:** Chỉ trả lời dựa trên Context và dữ liệu có sẵn. Nếu câu hỏi ngoài phạm vi du lịch hoặc thiếu dữ liệu, nói rõ: "Mình chưa có thông tin để trả lời câu hỏi này." Tuyệt đối không suy đoán hay bịa đặt.

    6. **Tiếp nối:** Kết thúc bằng đúng một câu hỏi liên quan hoặc đề xuất cụ thể. Nếu đã hỏi thông tin còn thiếu thì không hỏi thêm. Khi thiếu dữ liệu, nêu rõ giới hạn trước khi hướng người dùng sang chủ đề du lịch khác."""

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
