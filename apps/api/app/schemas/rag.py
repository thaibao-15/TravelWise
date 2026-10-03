"""
Pydantic schemas for RAG retrieval and semantic search.
"""

from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


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

