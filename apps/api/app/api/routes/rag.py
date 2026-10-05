import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from langchain_core.messages import AIMessage, HumanMessage
from sqlmodel import Session

from app.api.deps import get_current_user_optional, get_session
from app.core.config import settings
from app.models.user import User
from app.rag.chain import RAGChainError, get_rag_chain
from app.rag.llm import extract_response_text, get_chat_llm
from app.rag.retriever import RAGRetriever
from app.schemas.rag import (
    LLMTestRequest,
    LLMTestResponse,
    MessageResponse,
    RAGAskRequest,
    RAGAskResponse,
    RAGSearchRequest,
    RAGSearchResponse,
)
from app.services.conversation_service import ConversationService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/rag",
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
    summary="Ask TravelWise RAG with Memory",
    description="Hỏi đáp du lịch thông minh dựa trên cơ sở tri thức RAG và Conversation Memory.",
)
def ask_knowledge(
    request: RAGAskRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> RAGAskResponse:
    """Execute RAG question-answering with conversational context.

    Flow:
        1. Parse question (from request.message or request.query).
        2. Get existing conversation (with ownership check) or create new one.
        3. Load recent messages to construct conversation history.
        4. Contextualize user question using conversation history.
        5. Invoke RAG chain (Retriever -> Knowledge -> Prompt -> LLM).
        6. Save USER message and AI message to database.
        7. Update conversation.updated_at.
        8. Return response (backward-compatible).
    """
    user_question = request.get_question()

    # 1. Resolve or create conversation
    if request.conversation_id is not None:
        conversation = ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=request.conversation_id,
            current_user=current_user,
            check_ownership=True,
        )
    else:
        # Create initial conversation title from first question
        title = user_question[:60] + ("..." if len(user_question) > 60 else "")
        user_id = current_user.id if current_user else None
        conversation = ConversationService.create_conversation(
            session=session,
            user_id=user_id,
            title=title,
        )

    # 2. Load recent conversation history (5-10 messages)
    recent_messages = ConversationService.get_recent_messages(
        session=session,
        conversation_id=conversation.id,
        limit=10,
    )

    chat_history = []
    for msg in recent_messages:
        if msg.sender == "USER":
            chat_history.append(HumanMessage(content=msg.content))
        elif msg.sender == "AI":
            chat_history.append(AIMessage(content=msg.content))

    # 3. Contextualize question & invoke RAG chain
    try:
        chain = get_rag_chain()
        standalone_question = chain.contextualize_question(
            question=user_question,
            chat_history=chat_history,
        )

        result = chain.invoke(
            question=user_question,
            standalone_question=standalone_question,
            chat_history=chat_history,
        )
        answer = result["answer"]
    except RAGChainError as e:
        logger.error("RAG chain error: %s", e.message)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.",
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Unexpected error in /rag/ask: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi xử lý câu hỏi.",
        )

    # 4. Save messages to database
    ConversationService.save_message(
        session=session,
        conversation_id=conversation.id,
        sender="USER",
        content=user_question,
    )

    ai_msg = ConversationService.save_message(
        session=session,
        conversation_id=conversation.id,
        sender="AI",
        content=answer,
    )

    # 5. Update conversation updated_at
    ConversationService.update_conversation_timestamp(session, conversation)

    return RAGAskResponse(
        conversation_id=conversation.id,
        message=MessageResponse(
            id=ai_msg.id,
            sender=ai_msg.sender,
            content=ai_msg.content,
            created_at=ai_msg.created_at,
            audio_url=ai_msg.audio_url,
        ),
    )


@router.post(
    "/test-llm",
    response_model=LLMTestResponse,
    status_code=status.HTTP_200_OK,
    summary="Test LLM Connection",
    description="Kiểm tra kết nối trực tiếp từ FastAPI tới Chat Model (Gemini / OpenAI). Không expose API key.",
)
def test_llm_connection(request: LLMTestRequest) -> LLMTestResponse:
    """Minimal test endpoint verifying FastAPI can call the Chat Model and receive a response."""
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
