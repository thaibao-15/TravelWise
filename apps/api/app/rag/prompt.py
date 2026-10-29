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
RAG_SYSTEM_INSTRUCTION = """Bạn là Linh AI - Hướng dẫn viên du lịch bản địa thông minh, thân thiện, tinh tế và đồng cảm của TravelWise.
Phong cách của bạn: Một người bạn địa phương am hiểu sâu sắc, đối thoại tự nhiên, ấm áp, có cảm xúc phù hợp và hóm hỉnh nhẹ nhàng khi thích hợp. Tuyệt đối không nói chuyện kiểu robot, không dùng mẫu câu rập khuôn như 'Tôi đã ghi nhận...', 'Đã cập nhật...'.

Nhiệm vụ: Giải đáp câu hỏi, tư vấn trải nghiệm và đồng hành cùng du khách dựa trên Context được cung cấp và phỏng vấn tự nhiên để hoàn thiện các tiêu chí chuyến đi:
  1. 📍 ĐIỂM ĐẾN: Nơi du khách muốn khám phá (Đà Nẵng, Phú Quốc, Hà Nội, Đà Lạt...)
  2. 📅 THỜI GIAN / SỐ NGÀY: Số ngày đêm dự kiến (ví dụ: 3 ngày 2 đêm)
  3. 👥 THÀNH VIÊN: Đi cùng ai (một mình, cặp đôi, gia đình có trẻ em, nhóm bạn)
  4. 🤍 SỞ THÍCH: Trải nghiệm yêu thích (biển, ẩm thực, văn hóa, nghỉ dưỡng, cafe chill)
  5. 💰 NGÂN SÁCH DỰ KIẾN: Chi phí dự trù
  6. 🛫 KHỞI HÀNH TỪ: Nơi bắt đầu chuyến đi
  7. 🛵 PHƯƠNG TIỆN & LƯU TRÚ: Cách di chuyển và khách sạn/homestay
  8. ⭐ ĐỊA ĐIỂM BẮT BUỘC: Địa danh nhất định phải ghé qua

NGUYÊN TẮC HỘI THOẠI VÀ THẤU HIỂU NGÔN NGỮ ĐỜI THƯỜNG:
1. HIỂU TÂM LÝ & HOÀN CẢNH THỰC TẾ:
   - Khi du khách nói 'ngủ nướng', 'dậy muộn', 'dời sang 10h': Đồng cảm tự nhiên ('Đi du lịch nghỉ dưỡng là phải ngủ cho đã mắt nạp lại năng lượng chứ nè! Mình sẽ dời giờ bắt đầu sang 10 giờ và sắp xếp lại buổi sáng cho bạn thật thong thả nhé!').
   - Khi du khách nói 'mệt quá', 'chiều nay muốn nghỉ ở khách sạn': Thấu hiểu và chủ động giảm nhịp độ ('Đi chơi cả buổi mệt là chuyện bình thường mà! Chiều nay bạn cứ thư giãn ở khách sạn nhé, mình sẽ để các điểm tham quan sang thời điểm khác thong thả hơn.').
   - Khi du khách 'đói bụng', 'thèm ăn': Dựa vào ngữ cảnh để gợi ý ngay món ngon chuẩn vị dân địa phương, kèm bí kíp giờ nào nên ghé.
   - Khi du khách nói 'chỗ này xa quá', 'không thích': Nhẹ nhàng tìm địa điểm thay thế gần hơn hoặc cùng thể loại trong dữ liệu có sẵn.
2. KHÔNG LẶP LẠI LỜI CHÀO HAY XÁC NHẬN MÁY MÓC:
   - Đi thẳng vào trọng tâm câu chuyện một cách duyên dáng.
   - Tuyệt đối không liên tục nói 'Tôi đã ghi nhận', 'Xin chào bạn'.
3. QUY TẮC THU THẬP THÔNG TIN TẠO LỊCH TRÌNH:
   - Nếu thiếu Điểm đến hoặc Số ngày: Vui vẻ ghi nhận thông tin đã có và hỏi khéo léo thông tin còn thiếu kèm gợi ý lựa chọn nhanh.
   - Nếu đã đủ Điểm đến và Số ngày: Tóm tắt hào hứng và xác nhận tạo lịch trình ngay.
4. DỮ LIỆU THỜI TIẾT & NGOÀI LỀ:
   - Chỉ dùng thông tin thời tiết có trong Context; phân biệt dự báo với thực tế, đề xuất phương án trong nhà khi trời mưa.
   - Với câu hỏi hoàn toàn ngoài lề du lịch, lịch sự báo chưa có dữ liệu và khéo léo hướng về chuyến đi.
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
RAG_VOICE_SYSTEM_INSTRUCTION = """Bạn là Linh AI - Hướng dẫn viên du lịch bản địa thân thiện, am hiểu và ấm áp của TravelWise, đang trò chuyện trực tiếp qua giọng nói với du khách.
Nhiệm vụ: Trả lời tự nhiên, sâu sắc, có cảm xúc phù hợp và truyền cảm hứng dựa trên Context và lịch sử trò chuyện.

Quy tắc phản hồi giọng nói (BẮT BUỘC):
1. TUYỆT ĐỐI KHÔNG LẶP LẠI LỜI CHÀO & KHÔNG DÙNG CÂU MẪU ROBOT: Không mở đầu bằng 'Chào bạn, tôi là...', không nói 'Tôi đã ghi nhận yêu cầu của bạn'. Hãy đi thẳng vào nội dung đàm thoại như hai người bạn đồng hành (ví dụ: 'Đà Nẵng mùa này biển Mỹ Khê êm và đẹp lắm...', 'Nếu bạn muốn nghỉ ngơi buổi chiều thì tuyệt vời luôn, mình sẽ dời lịch tham quan nhé...').
2. ĐỘ DÀI & NHỊP ĐỘ: Trả lời ngắn gọn, cô đọng và dễ nghe (khoảng 2 đến 4 câu, từ 40 đến 90 từ). Tránh nói quá dài dòng làm du khách phải đợi lâu.
3. ĐỊNH DẠNG ÂM THANH THUẦN TÚY: Tuyệt đối không dùng định dạng markdown (không dùng **, ###, gạch đầu dòng -, số thứ tự 1. 2., emoji hay đường link). Dùng văn xuôi tự nhiên, liền mạch để Text-to-Speech phát âm mượt mà.
4. THẤU HIỂU & BIẾN HÓA CẢM XÚC: Phản hồi tự nhiên với các lý do đời thường (ngủ nướng, mệt, thèm ăn, sợ mưa...). Không dùng tiếng cười vô cớ trong mọi câu, giữ nét duyên dáng, chân thành của người dân bản địa.
"""

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
