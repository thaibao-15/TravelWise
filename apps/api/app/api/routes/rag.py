"""
FastAPI route for RAG retrieval and semantic knowledge search.
"""

from fastapi import APIRouter, status

from app.rag.retriever import RAGRetriever
from app.schemas.rag import RAGSearchRequest, RAGSearchResponse

router = APIRouter(
    prefix="/rag",
    tags=["RAG / Semantic Search"],
)


@router.post(
    "/search",
    response_model=RAGSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Semantic Search Knowledge",
    description="Tìm kiếm các đoạn knowledge liên quan nhất dựa trên semantic similarity search qua Chroma vector store.",
)
def search_knowledge(request: RAGSearchRequest) -> RAGSearchResponse:
    """Execute semantic search against the TravelWise knowledge base.

    - **query**: Câu hỏi hoặc từ khóa tìm kiếm (bắt buộc)
    - **top_k**: Số lượng kết quả liên quan tối đa cần lấy (mặc định: 3)
    """
    retriever = RAGRetriever()
    results = retriever.search(query=request.query, top_k=request.top_k)

    return RAGSearchResponse(
        query=request.query,
        results=results,
    )
