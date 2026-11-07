"""
RAG Chain module for TravelWise.

Connects Retriever + Prompt + LLM into a complete retrieval-augmented generation workflow.
Supports Conversation Memory with Conversational Question Contextualization.
Reuses existing retriever, prompt template, and LLM factories.
Ensures no API keys, credentials, or internal secrets are leaked in logs or exceptions.
"""

import base64
import logging
import mimetypes
import os
import re
from typing import Any, Dict, List, Optional, Sequence

from langchain_core.documents import Document
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import HumanMessage
from langchain_core.prompts import ChatPromptTemplate

from app.rag.config import RAG_TOP_K
from app.rag.llm import extract_response_text, get_chat_llm
from app.rag.prompt import (
    format_docs,
    get_contextualize_prompt,
    get_rag_prompt,
    get_rag_prompt_with_history,
    get_rag_voice_prompt,
    get_rag_voice_prompt_with_history,
)
from app.rag.retriever import RAGRetriever

logger = logging.getLogger(__name__)


def resolve_image_to_data_uri(img_path_or_url: str) -> str:
    """Convert a local file path, static upload URL, or public URL to base64 Data URI for LLM vision processing."""
    if not img_path_or_url:
        return ""
    if img_path_or_url.startswith("data:"):
        return img_path_or_url

    clean_path = img_path_or_url.split("?")[0]
    filename = os.path.basename(clean_path)

    # 1. Search candidate upload directories across possible workspace locations
    candidate_dirs = [
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "uploads"),
        r"D:\TravelWise\TravelWise\apps\api\app\static\uploads",
        r"D:\TravelWise 1\TravelWise\apps\api\app\static\uploads",
        r"D:\TravelWise2\TravelWise\apps\api\app\static\uploads",
    ]
    for c_dir in candidate_dirs:
        candidate_file = os.path.join(c_dir, filename)
        if os.path.isfile(candidate_file):
            try:
                mime_type, _ = mimetypes.guess_type(candidate_file)
                mime_type = mime_type or "image/jpeg"
                with open(candidate_file, "rb") as f:
                    b64 = base64.b64encode(f.read()).decode("utf-8")
                return f"data:{mime_type};base64,{b64}"
            except Exception as e:
                logger.warning("Failed to encode local image to base64: %s", e)

    # 2. If it's a local HTTP URL or relative static path, fetch bytes from local server
    if "127.0.0.1" in img_path_or_url or "localhost" in img_path_or_url or img_path_or_url.startswith("/"):
        try:
            import requests

            target_url = img_path_or_url
            if target_url.startswith("/"):
                target_url = f"http://127.0.0.1:8000{target_url}"
            resp = requests.get(target_url, timeout=5)
            if resp.status_code == 200:
                content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0]
                b64 = base64.b64encode(resp.content).decode("utf-8")
                return f"data:{content_type};base64,{b64}"
        except Exception as e:
            logger.warning("Failed to fetch local image via HTTP: %s", e)

    return img_path_or_url


def attach_images_to_messages(messages: Sequence[Any], image_urls: Optional[Sequence[str]]) -> List[Any]:
    """Wraps user message with Multimodal image blocks for Gemini/GPT vision processing."""
    if not image_urls:
        return list(messages)

    resolved_uris = [resolve_image_to_data_uri(u) for u in image_urls if u]
    if not resolved_uris:
        return list(messages)

    messages_copy = list(messages)
    last_msg = messages_copy[-1]
    existing_text = extract_response_text(getattr(last_msg, "content", last_msg))

    guidance = (
        "\n\n[HƯỚNG DẪN NHẬN DIỆN THỊ GIÁC]: "
        "Người dùng đã đính kèm hình ảnh địa điểm du lịch. Hãy quan sát thật kỹ các đặc điểm kiến trúc, "
        "danh lam thắng cảnh, màu sắc, phong cảnh thiên nhiên hoặc chi tiết nổi bật trong ảnh để xác định chính xác "
        "đây là địa điểm nào (nêu rõ tên địa danh, thành phố/tỉnh thành). Sau đó hãy giới thiệu ngắn gọn, cung cấp các thông tin "
        "hữu ích như vị trí, điểm nổi bật, trải nghiệm du lịch tại nơi này."
    )

    content_parts: List[Dict[str, Any]] = [
        {"type": "text", "text": f"{existing_text}{guidance}"}
    ]
    for uri in resolved_uris:
        content_parts.append({
            "type": "image_url",
            "image_url": {"url": uri}
        })

    messages_copy[-1] = HumanMessage(content=content_parts)
    return messages_copy


_V_CAP = r"[A-ZÀÁẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬĐÈÉẺẼẸÊẾỀỂỄỆÌÍỈĨỊÒÓỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÙÚỦŨỤƯỨỪỬỮỰỲÝỶỸỴ][a-zà-ỹ0-9]*"
_PREFIX_PATTERN = re.compile(
    rf"(?i:\b(?:chùa|núi|đèo|bãi biển|bãi|vịnh|bán đảo|bảo tàng|cầu|chợ|lăng|tháp|khu du lịch|đảo|thác|hồ|phố cổ)\s+)({_V_CAP}(?:\s+{_V_CAP}){{0,2}})"
)
_CAP_PATTERN = re.compile(rf"\b({_V_CAP}(?:\s+{_V_CAP}){{1,3}})\b")
_IGNORED_ENTITIES = {
    "travelwise", "travelwise ai", "linh ai", "xin chào", "chào bạn", "cảm ơn", "tôi là", "bạn là"
}


def extract_entities_from_text(content: str) -> List[str]:
    """Extract location/place entities from text using fast regex heuristics (<1ms)."""
    results: List[str] = []
    if not content:
        return results

    for m in _PREFIX_PATTERN.finditer(content):
        cand = m.group(0).strip()
        if cand.lower() not in _IGNORED_ENTITIES and len(cand) >= 3 and cand not in results:
            results.append(cand)

    for m in _CAP_PATTERN.finditer(content):
        cand = m.group(1).strip()
        if cand.lower() not in _IGNORED_ENTITIES and len(cand) >= 3 and cand not in results:
            results.append(cand)

    return results


def extract_recent_entity(chat_history: Optional[Sequence[Any]]) -> Optional[str]:
    """Extract the most relevant recent place or location entity from conversation history."""
    if not chat_history:
        return None

    recent_messages = list(chat_history)[-4:]
    recent_messages.reverse()

    # Priority 1: User's previous question (most direct subject of discussion)
    for msg in recent_messages:
        if isinstance(msg, HumanMessage) or getattr(msg, "type", None) == "human":
            content = extract_response_text(getattr(msg, "content", msg))
            entities = extract_entities_from_text(content)
            if entities:
                return entities[0]

    # Priority 2: AI's previous responses
    for msg in recent_messages:
        content = extract_response_text(getattr(msg, "content", msg))
        entities = extract_entities_from_text(content)
        if entities:
            return entities[0]

    return None


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
        self.voice_prompt = get_rag_voice_prompt()
        self.voice_prompt_with_history = get_rag_voice_prompt_with_history()
        self.contextualize_prompt = contextualize_prompt or get_contextualize_prompt()
        self.top_k = top_k or RAG_TOP_K

    def contextualize_question(
        self,
        question: str,
        chat_history: Optional[Sequence[Any]] = None,
    ) -> str:
        """Formulate a standalone question for ChromaDB using zero-latency Heuristic Entity Stitching (<1ms).

        Eliminates the expensive 1.7s secondary LLM call while maintaining high retrieval precision.

        Args:
            question: Current user question (e.g. "Nó có gì đặc biệt?")
            chat_history: Sequence of previous messages (HumanMessage, AIMessage).

        Returns:
            Standalone rewritten question (e.g. "Chùa Linh Ứng Nó có gì đặc biệt?")
        """
        clean_question = (question or "").strip()
        if not clean_question or not chat_history:
            return clean_question

        lower_q = clean_question.lower()

        # Check if the question already explicitly mentions its own location entity
        question_entities = extract_entities_from_text(clean_question)
        if question_entities:
            # Question is already specific and standalone
            return clean_question

        context_cues = (
            "nó", "đó", "đấy", "ở đó", "ở đây", "chỗ này", "chỗ đó", "nơi đó", "chúng",
            "họ", "vé vào", "mấy giờ", "giá bao nhiêu", "còn gì", "đi thế nào",
            "ở đâu", "mở cửa", "gần không", "cách bao xa", "bao tiền", "bao nhiêu tiền",
            "đường đi", "cách nào", "phương tiện gì", "có gì", "ăn gì", "chơi gì"
        )
        has_context_cue = any(cue in lower_q for cue in context_cues)
        word_count = len(clean_question.split())

        # If question has >= 5 words and no contextual pronouns, it's considered standalone
        if not has_context_cue and word_count >= 5:
            return clean_question

        # Extract recent place/location entity from conversation history
        recent_entity = extract_recent_entity(chat_history)
        if recent_entity and recent_entity.lower() not in lower_q:
            stitched_query = f"{recent_entity} {clean_question}"
            logger.info(
                "Heuristic contextualized question: '%s' -> '%s'",
                clean_question,
                stitched_query,
            )
            return stitched_query

        return clean_question

    def invoke(
        self,
        question: str,
        standalone_question: Optional[str] = None,
        chat_history: Optional[Sequence[Any]] = None,
        planning_summary: Optional[str] = None,
        top_k: Optional[int] = None,
        mode: str = "chat",
        location_context: Optional[str] = None,
        weather_context: Optional[str] = None,
        image_urls: Optional[Sequence[str]] = None,
        retrieved_docs: Optional[List[Document]] = None,
    ) -> Dict[str, Any]:
        """Execute the RAG pipeline for a given question and optional conversation context.

        Flow:
            1. Validate user question.
            2. Determine search query (standalone_question if provided, else clean_question).
            3. Retrieve top-K relevant documents from vector store (if not pre-retrieved).
            4. Build formatted context string.
            5. Fill prompt template (standard or voice-optimized).
            6. Invoke LLM and extract text response.
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

        # 2. Retrieve relevant documents using the standalone contextualized query if not provided
        if retrieved_docs is None:
            try:
                retrieved_docs = self.retriever.search(query=search_query, top_k=k)
            except Exception as e:
                logger.error("RAG retrieval failed: %s", type(e).__name__)
                retrieved_docs = []

        # 3. Handle documents found or fallback
        if not retrieved_docs:
            if not chat_history and not planning_summary and not image_urls:
                return {
                    "question": clean_question,
                    "standalone_question": search_query,
                    "answer": "Xin lỗi, hiện tại tôi không tìm thấy đủ thông tin về vấn đề này trong cơ sở dữ liệu để giải đáp cho bạn.",
                    "sources": [],
                }
            if image_urls:
                context_text = (
                    "Người dùng đã đính kèm hình ảnh. Hãy quan sát hình ảnh và phân tích đặc điểm kiến trúc, danh lam thắng cảnh để giải đáp chính xác."
                )
            else:
                context_text = (
                    "Không có tài liệu địa danh cụ thể nào cho câu hỏi này. "
                    "Hãy đóng vai trò Trợ lý Lập kế hoạch Du lịch TravelWise để tư vấn và phỏng vấn các thông tin chuyến đi còn thiếu trong Checklist."
                )
        else:
            context_text = format_docs(retrieved_docs)

        # 4. Inject planning context summary if available
        if planning_summary:
            context_text = (
                f"{context_text}\n\n"
                f"=== BẢNG TIÊU CHÍ KẾ HOẠCH CHUYẾN ĐI HIỆN TẠI ===\n"
                f"{planning_summary}\n"
            )
        if location_context:
            context_text = f"{context_text}\n\n=== VỊ TRÍ HIỆN TẠI CỦA NGƯỜI DÙNG ===\n{location_context}\n"
        if weather_context:
            context_text = f"{context_text}\n\n{weather_context}\n"

        # 5. Format prompt (use voice prompt for voice mode, otherwise standard prompt)
        try:
            if mode == "voice":
                target_prompt = self.voice_prompt_with_history if chat_history else self.voice_prompt
            else:
                target_prompt = self.prompt_with_history if chat_history else self.prompt

            if chat_history:
                formatted_messages = target_prompt.format_messages(
                    context=context_text,
                    chat_history=list(chat_history),
                    question=clean_question,
                )
            else:
                formatted_messages = target_prompt.format_messages(
                    context=context_text,
                    question=clean_question,
                )
        except Exception as e:
            logger.error("RAG prompt formatting error: %s", type(e).__name__)
            raise RAGChainError("Lỗi định dạng câu hỏi và ngữ cảnh.") from None

        # 6. Invoke LLM
        try:
            if image_urls:
                formatted_messages = attach_images_to_messages(formatted_messages, image_urls)
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

    async def ainvoke(
        self,
        question: str,
        standalone_question: Optional[str] = None,
        chat_history: Optional[Sequence[Any]] = None,
        planning_summary: Optional[str] = None,
        top_k: Optional[int] = None,
        mode: str = "chat",
        location_context: Optional[str] = None,
        weather_context: Optional[str] = None,
        image_urls: Optional[Sequence[str]] = None,
        retrieved_docs: Optional[List[Document]] = None,
    ) -> Dict[str, Any]:
        """Asynchronous execution of the RAG pipeline."""
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

        # 2. Retrieve relevant documents using thread pool if not provided
        if retrieved_docs is None:
            try:
                import asyncio
                retrieved_docs = await asyncio.to_thread(self.retriever.search, query=search_query, top_k=k)
            except Exception as e:
                logger.error("RAG retrieval failed: %s", type(e).__name__)
                retrieved_docs = []

        # 3. Handle documents found or fallback
        if not retrieved_docs:
            if not chat_history and not planning_summary and not image_urls:
                return {
                    "question": clean_question,
                    "standalone_question": search_query,
                    "answer": "Xin lỗi, hiện tại tôi không tìm thấy đủ thông tin về vấn đề này trong cơ sở dữ liệu để giải đáp cho bạn.",
                    "sources": [],
                }
            if image_urls:
                context_text = (
                    "Người dùng đã đính kèm hình ảnh. Hãy quan sát hình ảnh và phân tích đặc điểm kiến trúc, danh lam thắng cảnh để giải đáp chính xác."
                )
            else:
                context_text = (
                    "Không có tài liệu địa danh cụ thể nào cho câu hỏi này. "
                    "Hãy đóng vai trò Trợ lý Lập kế hoạch Du lịch TravelWise để tư vấn và phỏng vấn các thông tin chuyến đi còn thiếu trong Checklist."
                )
        else:
            context_text = format_docs(retrieved_docs)

        # 4. Inject planning context summary if available
        if planning_summary:
            context_text = (
                f"{context_text}\n\n"
                f"=== BẢNG TIÊU CHÍ KẾ HOẠCH CHUYẾN ĐI HIỆN TẠI ===\n"
                f"{planning_summary}\n"
            )
        if location_context:
            context_text = f"{context_text}\n\n=== VỊ TRÍ HIỆN TẠI CỦA NGƯỜI DÙNG ===\n{location_context}\n"
        if weather_context:
            context_text = f"{context_text}\n\n{weather_context}\n"

        # 5. Format prompt (use voice prompt for voice mode, otherwise standard prompt)
        try:
            if mode == "voice":
                target_prompt = self.voice_prompt_with_history if chat_history else self.voice_prompt
            else:
                target_prompt = self.prompt_with_history if chat_history else self.prompt

            if chat_history:
                formatted_messages = target_prompt.format_messages(
                    context=context_text,
                    chat_history=list(chat_history),
                    question=clean_question,
                )
            else:
                formatted_messages = target_prompt.format_messages(
                    context=context_text,
                    question=clean_question,
                )
        except Exception as e:
            logger.error("RAG prompt formatting error: %s", type(e).__name__)
            raise RAGChainError("Lỗi định dạng câu hỏi và ngữ cảnh.") from None

        # 6. Invoke LLM (using ainvoke if available, otherwise asyncio.to_thread)
        try:
            if image_urls:
                formatted_messages = attach_images_to_messages(formatted_messages, image_urls)
            if hasattr(self.llm, "ainvoke") and callable(getattr(self.llm, "ainvoke", None)):
                llm_response = await self.llm.ainvoke(formatted_messages)
            else:
                import asyncio
                llm_response = await asyncio.to_thread(self.llm.invoke, formatted_messages)
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

    def stream_answer(
        self,
        question: str,
        standalone_question: Optional[str] = None,
        chat_history: Optional[Sequence[Any]] = None,
        planning_summary: Optional[str] = None,
        top_k: Optional[int] = None,
        mode: str = "chat",
        location_context: Optional[str] = None,
        weather_context: Optional[str] = None,
        image_urls: Optional[Sequence[str]] = None,
        retrieved_docs: Optional[List[Document]] = None,
    ):
        """Stream response tokens generator for real-time low-latency response."""
        clean_question = (question or "").strip()
        if not clean_question:
            yield "Vui lòng nhập câu hỏi để TravelWise có thể hỗ trợ bạn."
            return

        k = 4 if mode == "voice" else (top_k or self.top_k)
        search_query = (standalone_question or clean_question).strip()

        if retrieved_docs is None:
            try:
                retrieved_docs = self.retriever.search(query=search_query, top_k=k)
            except Exception as e:
                logger.error("RAG retrieval failed: %s", type(e).__name__)
                retrieved_docs = []

        if not retrieved_docs:
            if image_urls:
                context_text = (
                    "Người dùng đã đính kèm hình ảnh. Hãy quan sát hình ảnh và phân tích đặc điểm kiến trúc, danh lam thắng cảnh để giải đáp chính xác."
                )
            else:
                context_text = (
                    "Không có tài liệu địa danh cụ thể nào cho câu hỏi này. "
                    "Hãy đóng vai trò Trợ lý Lập kế hoạch Du lịch TravelWise để tư vấn và phỏng vấn các thông tin chuyến đi còn thiếu trong Checklist."
                )
        else:
            context_text = format_docs(retrieved_docs)

        # Inject planning context summary if available
        if planning_summary:
            context_text = (
                f"{context_text}\n\n"
                f"=== BẢNG TIÊU CHÍ KẾ HOẠCH CHUYẾN ĐI HIỆN TẠI ===\n"
                f"{planning_summary}\n"
            )
        if location_context:
            context_text = f"{context_text}\n\n=== VỊ TRÍ HIỆN TẠI CỦA NGƯỜI DÙNG ===\n{location_context}\n"
        if weather_context:
            context_text = f"{context_text}\n\n{weather_context}\n"

        try:
            if mode == "voice":
                target_prompt = self.voice_prompt_with_history if chat_history else self.voice_prompt
            else:
                target_prompt = self.prompt_with_history if chat_history else self.prompt

            if chat_history:
                formatted_messages = target_prompt.format_messages(
                    context=context_text,
                    chat_history=list(chat_history),
                    question=clean_question,
                )
            else:
                formatted_messages = target_prompt.format_messages(
                    context=context_text,
                    question=clean_question,
                )
        except Exception as e:
            logger.error("RAG prompt formatting error: %s", type(e).__name__)
            raise RAGChainError("Lỗi định dạng câu hỏi và ngữ cảnh.") from None

        try:
            if image_urls:
                formatted_messages = attach_images_to_messages(formatted_messages, image_urls)
            for chunk in self.llm.stream(formatted_messages):
                token = extract_response_text(getattr(chunk, "content", chunk))
                if token:
                    yield token
        except Exception as e:
            logger.error("RAG LLM stream error: %s", type(e).__name__)
            raise RAGChainError("Đã xảy ra lỗi trong quá trình tạo câu trả lời.") from None


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
