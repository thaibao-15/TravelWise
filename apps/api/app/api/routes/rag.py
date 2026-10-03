import logging
from fastapi import APIRouter, HTTPException, status

from app.core.config import settings
from app.rag.chain import RAGChainError, get_rag_chain
from app.rag.llm import extract_response_text, get_chat_llm
from app.rag.retriever import RAGRetriever
from app.schemas.rag import (
    LLMTestRequest,
    LLMTestResponse,
    RAGAskRequest,
    RAGAskResponse,
    RAGSearchRequest,
    RAGSearchResponse,
)

logger = logging.getLogger(__name__)

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


@router.post(
    "/ask",
    response_model=RAGAskResponse,
    status_code=status.HTTP_200_OK,
    summary="Ask TravelWise RAG",
    description="Hỏi đáp du lịch thông minh dựa trên cơ sở tri thức đã lưu trong vector database thông qua RAG Chain.",
)
def ask_knowledge(request: RAGAskRequest) -> RAGAskResponse:
    """Execute RAG question-answering.

    Flow:
        Router -> Service/RAGChain -> Retriever -> Chroma -> Prompt -> LLM -> Response
    """
    try:
        chain = get_rag_chain()
        result = chain.invoke(question=request.query)
        return RAGAskResponse(
            query=request.query,
            answer=result["answer"],
        )
    except RAGChainError as e:
        logger.error("RAG chain error: %s", e.message)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.",
        )
    except Exception as e:
        logger.error("Unexpected error in /rag/ask: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi xử lý câu hỏi.",
        )



@router.post(
    "/test-llm",
    response_model=LLMTestResponse,
    status_code=status.HTTP_200_OK,
    summary="Test LLM Connection",
    description="Kiểm tra kết nối trực tiếp từ FastAPI tới Chat Model (Gemini / OpenAI). Không expose API key.",
)
def test_llm_connection(request: LLMTestRequest) -> LLMTestResponse:
    """Minimal test endpoint verifying FastAPI can call the Chat Model and receive a response.

    - Does not expose the API key in logs or error responses.
    - Model & Provider are resolved from settings (not hardcoded).
    """
    try:
        llm = get_chat_llm()
        response = llm.invoke(request.prompt)
        response_text = extract_response_text(getattr(response, "content", response))

        provider = (settings.LLM_PROVIDER or "gemini").lower()
        active_model = settings.GEMINI_MODEL if provider == "gemini" else settings.OPENAI_MODEL

        return LLMTestResponse(
            status="success",
            provider=provider,
            model=active_model,
            response=response_text,
        )
    except ValueError as e:
        logger.warning("LLM configuration error during test: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e),
        )
    except Exception as e:
        logger.error("LLM execution error during test: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to communicate with LLM service.",
        )

