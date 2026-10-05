"""
Pydantic schemas for RAG retrieval and semantic search.
"""

from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class RAGSearchRequest(BaseModel):
    """Request payload for semantic knowledge search."""

    query: str = Field(
        ...,
        min_length=1,
        description="Nội dung câu hỏi hoặc từ khóa tìm kiếm",
        examples=["Chùa Linh Ứng có gì đặc biệt?"],
    )
    top_k: int = Field(
        default=3,
        gt=0,
        le=50,
        description="Số lượng chunks liên quan nhất cần trả về",
        examples=[3],
    )

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "query": "Chùa Linh Ứng có gì đặc biệt?",
                "top_k": 3,
            }
        }
    )


class RAGSearchMetadata(BaseModel):
    """Metadata associated with a retrieved knowledge chunk."""

    knowledge_id: Optional[int] = None
    place_id: Optional[int] = None
    place_name: Optional[str] = None
    place_address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    title: Optional[str] = None
    source: Optional[str] = None
    chunk_index: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class RAGSearchResultItem(BaseModel):
    """A single retrieved chunk with its relevance score and metadata."""

    content: str
    score: float
    metadata: RAGSearchMetadata

    model_config = ConfigDict(from_attributes=True)


class RAGSearchResponse(BaseModel):
    """Response payload containing query and matching knowledge chunks."""

    query: str
    results: List[RAGSearchResultItem]

    model_config = ConfigDict(from_attributes=True)


class LLMTestRequest(BaseModel):
    """Minimal request schema for testing LLM connection."""

    prompt: str = Field(
        default="Xin chào, bạn có thể giúp tôi lên kế hoạch du lịch không?",
        description="Prompt test gửi tới OpenAI LLM",
        examples=["Xin chào, bạn là ai?"],
    )


class LLMTestResponse(BaseModel):
    """Response schema from minimal LLM test endpoint."""

    status: str
    provider: str
    model: str
    response: str


from datetime import datetime
from typing import Any


class MessageResponse(BaseModel):
    """Payload representing a single saved chat message."""

    id: int
    sender: str
    content: str
    created_at: datetime
    audio_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class RAGAskRequest(BaseModel):
    """Request payload for RAG question-answering with optional conversation memory."""

    query: Optional[str] = Field(
        default=None,
        description="Nội dung câu hỏi du lịch của người dùng (tương thích ngược)",
        examples=["Chùa Linh Ứng có gì đặc biệt?"],
    )
    message: Optional[str] = Field(
        default=None,
        description="Nội dung câu hỏi hoặc tin nhắn",
        examples=["Nó có gì đặc biệt?"],
    )
    conversation_id: Optional[int] = Field(
        default=None,
        description="ID cuộc trò chuyện (nếu tiếp tục hội thoại)",
        examples=[15],
    )

    @field_validator("query", "message")
    @classmethod
    def clean_text(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            stripped = v.strip()
            return stripped if stripped else None
        return None

    @model_validator(mode="after")
    def validate_content(self) -> "RAGAskRequest":
        q = (self.message or self.query or "").strip()
        if not q:
            raise ValueError("Cần cung cấp nội dung câu hỏi ('message' hoặc 'query').")
        return self

    def get_question(self) -> str:
        q = (self.message or self.query or "").strip()
        if not q:
            raise ValueError("Cần cung cấp nội dung câu hỏi ('message' hoặc 'query').")
        return q

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "conversation_id": 15,
                "message": "Nó có gì đặc biệt?",
            }
        }
    )


class RAGAskResponse(BaseModel):
    """Response payload for RAG question-answering with conversational message."""

    conversation_id: int
    message: MessageResponse

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "conversation_id": 15,
                "message": {
                    "id": 42,
                    "sender": "AI",
                    "content": "Chùa Linh Ứng - Bãi Bụt nổi bật với tượng Phật Quan Thế Âm cao 67m...",
                    "created_at": "2026-10-05T08:00:00Z",
                    "audio_url": None,
                },
            }
        },
    )

