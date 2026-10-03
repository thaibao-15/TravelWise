"""
Pydantic schemas for RAG retrieval and semantic search.
"""

from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field, field_validator


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


class RAGAskRequest(BaseModel):
    """Request payload for RAG question-answering."""

    query: str = Field(
        ...,
        min_length=1,
        description="Nội dung câu hỏi du lịch của người dùng",
        examples=["Chùa Linh Ứng có gì đặc biệt?"],
    )

    @field_validator("query")
    @classmethod
    def validate_query(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("Query không được để trống hoặc chỉ chứa khoảng trắng.")
        return stripped

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "query": "Chùa Linh Ứng có gì đặc biệt?"
            }
        }
    )


class RAGAskResponse(BaseModel):
    """Response payload for RAG question-answering."""

    query: str
    answer: str

    model_config = ConfigDict(from_attributes=True)

