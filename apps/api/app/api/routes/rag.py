import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from langchain_core.messages import AIMessage, HumanMessage
from sqlalchemy.exc import SQLAlchemyError
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
from app.services.conversation_summary_service import (
    ConversationSummaryError,
    ConversationSummaryService,
)
from app.services.weather_context_service import WeatherContextService

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
    location_context = (
        f"Vĩ độ: {request.current_location.latitude:.6f}, "
        f"Kinh độ: {request.current_location.longitude:.6f}. "
        "Hãy dùng vị trí này làm vị trí hiện tại của người dùng; "
        "không suy đoán địa chỉ cụ thể nếu không có dữ liệu bản đồ xác nhận."
        if request.current_location
        else None
    )

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

    # 2. Save USER message to database
    user_msg = ConversationService.save_message(
        session=session,
        conversation_id=conversation.id,
        sender="USER",
        content=user_question,
    )

    # 3. Extract and update TripPlanningContext if relevant (non-blocking for chat failure)
    planning_context = None
    try:
        from app.services.trip_planning_service import TripPlanningContextExtractionService

        planning_context = TripPlanningContextExtractionService.extract_and_update_trip_context(
            session=session,
            conversation_id=conversation.id,
            current_user=current_user,
            latest_message=user_msg,
        )
    except Exception as e:
        logger.error("Planning context extraction error for conversation %s: %s", conversation.id, e)

    # 4. Load persisted summaries and recent conversation history.
    try:
        current_summary = ConversationSummaryService.get_summary(
            session=session,
            conversation_id=conversation.id,
            user_id=conversation.user_id,
        )
        previous_summaries = ConversationSummaryService.get_recent_user_summaries(
            session=session,
            user_id=conversation.user_id,
            exclude_conversation_id=conversation.id,
        )
    except SQLAlchemyError as exc:
        logger.warning(
            "Conversation summary context unavailable for conversation %s: %s",
            conversation.id,
            type(exc).__name__,
        )
        current_summary = None
        previous_summaries = []
    recent_messages = ConversationService.get_recent_messages(
        session=session,
        conversation_id=conversation.id,
        limit=10,
    )

    chat_history = ConversationSummaryService.build_context_history(
        current_summary,
        previous_summaries,
    )
    for msg in recent_messages:
        if msg.id == user_msg.id:
            continue  # Avoid duplicating the current question in historical context
        if msg.sender == "USER":
            chat_history.append(HumanMessage(content=msg.content))
        elif msg.sender == "AI":
            chat_history.append(AIMessage(content=msg.content))

    # 5. Contextualize question & invoke RAG chain
    try:
        chain = get_rag_chain()
        standalone_question = chain.contextualize_question(
            question=user_question,
            chat_history=chat_history,
        )

        planning_summary = ""
        if planning_context:
            planning_summary = TripPlanningContextExtractionService.format_context_summary(planning_context)

        weather_question = (
            standalone_question if isinstance(standalone_question, str) else user_question
        )
        weather_context = WeatherContextService.build_context_sync(
            session=session,
            question=weather_question,
            current_location=request.current_location,
        )
        result = chain.invoke(
            question=user_question,
            standalone_question=standalone_question,
            chat_history=chat_history,
            planning_summary=planning_summary,
            mode=request.mode or "chat",
            location_context=location_context,
            weather_context=weather_context,
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

    # 6. Save AI message to database
    ai_msg = ConversationService.save_message(
        session=session,
        conversation_id=conversation.id,
        sender="AI",
        content=answer,
    )

    try:
        ConversationSummaryService.maybe_update_summary(
            session=session,
            conversation_id=conversation.id,
            user_id=conversation.user_id,
        )
    except ConversationSummaryError:
        logger.warning(
            "Conversation summary skipped after chat response for conversation %s",
            conversation.id,
        )

    # 7. Update conversation updated_at
    ConversationService.update_conversation_timestamp(session, conversation)

    # 8. Compute planning status and intent action
    planning_status = None
    is_ready = False
    planning_action = None
    if planning_context:
        is_ready = bool(planning_context.planning_state.is_ready_to_generate)
        planning_status = "READY_TO_GENERATE" if is_ready else "COLLECTING_REQUIREMENTS"
        clean_q = user_question.lower()
        gen_cues = (
            "tạo lịch trình", "lên lịch trình", "tạo giúp mình", "tạo đi",
            "đồng ý", "ok tạo đi", "lên kế hoạch đi", "tạo ngay", "làm lịch trình", "tạo cho mình",
        )
        if any(cue in clean_q for cue in gen_cues):
            planning_action = "TRIGGER_GENERATION"
        elif any(cue in clean_q for cue in ("lưu chuyến đi", "lưu lại", "xác nhận lưu", "lưu lịch trình")):
            planning_action = "TRIGGER_SAVE"

    return RAGAskResponse(
        conversation_id=conversation.id,
        message=MessageResponse(
            id=ai_msg.id,
            sender=ai_msg.sender,
            content=ai_msg.content,
            created_at=ai_msg.created_at,
            audio_url=ai_msg.audio_url,
        ),
        planning_context=planning_context,
        planning_status=planning_status,
        is_ready_to_generate=is_ready,
        planning_action=planning_action,
    )


@router.post(
    "/ask-stream",
    summary="Hỏi đáp AI có phản hồi thời gian thực qua Streaming (SSE)",
    description="Stream trực tiếp từng token từ LLM qua Server-Sent Events giúp giảm tối đa độ trễ phản hồi cho người dùng.",
)
async def ask_rag_stream(
    request: RAGAskRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    import json
    from fastapi.responses import StreamingResponse

    user_question = request.get_question()
    location_context = (
        f"Vĩ độ: {request.current_location.latitude:.6f}, "
        f"Kinh độ: {request.current_location.longitude:.6f}. "
        "Hãy dùng vị trí này làm vị trí hiện tại của người dùng; "
        "không suy đoán địa chỉ cụ thể nếu không có dữ liệu bản đồ xác nhận."
        if request.current_location
        else None
    )

    # 1. Resolve or create conversation with ownership check
    if request.conversation_id is not None:
        conversation = ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=request.conversation_id,
            current_user=current_user,
            check_ownership=True,
        )
    else:
        title = user_question[:60] + ("..." if len(user_question) > 60 else "")
        user_id = current_user.id if current_user else None
        conversation = ConversationService.create_conversation(
            session=session,
            user_id=user_id,
            title=title,
        )

<<<<<<< HEAD
    # 2. Save USER message to database FIRST so context extraction has access to it
    user_msg = ConversationService.save_message(
        session=session,
        conversation_id=conversation.id,
        sender="USER",
        content=user_question,
    )

    # 3. Extract and update TripPlanningContext BEFORE generating response
    planning_context = None
    try:
        from app.services.trip_planning_service import TripPlanningContextExtractionService

        planning_context = TripPlanningContextExtractionService.extract_and_update_trip_context(
            session=session,
            conversation_id=conversation.id,
            current_user=current_user,
            latest_message=user_msg,
        )
    except Exception as e:
        logger.error("Planning context extraction error for stream: %s", e)

    planning_summary = ""
    planning_status = None
    is_ready = False
    planning_action = None
    if planning_context:
        from app.services.trip_planning_service import TripPlanningContextExtractionService

        planning_summary = TripPlanningContextExtractionService.format_context_summary(planning_context)
        is_ready = bool(planning_context.planning_state.is_ready_to_generate)
        planning_status = "READY_TO_GENERATE" if is_ready else "COLLECTING_REQUIREMENTS"
        clean_q = user_question.lower()
        gen_cues = (
            "tạo lịch trình", "lên lịch trình", "tạo giúp mình", "tạo đi",
            "đồng ý", "ok tạo đi", "lên kế hoạch đi", "tạo ngay", "làm lịch trình", "tạo cho mình",
        )
        if any(cue in clean_q for cue in gen_cues):
            planning_action = "TRIGGER_GENERATION"
        elif any(cue in clean_q for cue in ("lưu chuyến đi", "lưu lại", "xác nhận lưu", "lưu lịch trình")):
            planning_action = "TRIGGER_SAVE"

    # 4. Load recent conversation history (excluding current user message to avoid duplicate)
=======
    try:
        current_summary = ConversationSummaryService.get_summary(
            session=session,
            conversation_id=conversation.id,
            user_id=conversation.user_id,
        )
        previous_summaries = ConversationSummaryService.get_recent_user_summaries(
            session=session,
            user_id=conversation.user_id,
            exclude_conversation_id=conversation.id,
        )
    except SQLAlchemyError as exc:
        logger.warning(
            "Conversation summary context unavailable for streaming conversation %s: %s",
            conversation.id,
            type(exc).__name__,
        )
        current_summary = None
        previous_summaries = []
>>>>>>> f9b663cb7c90353a668cb84d3b71b42ba678d896
    recent_messages = ConversationService.get_recent_messages(
        session=session,
        conversation_id=conversation.id,
        limit=10,
    )

    chat_history = ConversationSummaryService.build_context_history(
        current_summary,
        previous_summaries,
    )
    for msg in recent_messages:
        if msg.id == user_msg.id:
            continue
        if msg.sender == "USER":
            chat_history.append(HumanMessage(content=msg.content))
        elif msg.sender == "AI":
            chat_history.append(AIMessage(content=msg.content))

    chain = get_rag_chain()
    if request.mode == "voice":
        standalone_question = user_question
    else:
        standalone_question = chain.contextualize_question(
            question=user_question,
            chat_history=chat_history,
        )

<<<<<<< HEAD
=======
    planning_summary = ""
    try:
        from app.services.trip_planning_service import TripPlanningContextExtractionService

        existing_ctx = TripPlanningContextExtractionService.get_planning_context_by_conversation(
            session=session,
            conversation_id=conversation.id,
            current_user=current_user,
            check_ownership=False,
        )
        if existing_ctx:
            planning_summary = TripPlanningContextExtractionService.format_context_summary(existing_ctx)
    except Exception as e:
        logger.debug("Could not retrieve existing planning context for stream: %s", e)

    weather_question = (
        standalone_question if isinstance(standalone_question, str) else user_question
    )
    weather_context = await WeatherContextService.build_context(
        session=session,
        question=weather_question,
        current_location=request.current_location,
    )

>>>>>>> f9b663cb7c90353a668cb84d3b71b42ba678d896
    async def event_generator():
        # Event 1: Init
        yield f"data: {json.dumps({'type': 'init', 'conversation_id': conversation.id}, ensure_ascii=False)}\n\n"

        # Event 2: Planning status (if context exists)
        if planning_context:
            planning_status_event = {
                "type": "planning_status",
                "conversation_id": conversation.id,
                "planning_status": planning_status,
                "is_ready_to_generate": is_ready,
                "planning_action": planning_action,
                "destination": planning_context.trip.destination.city,
                "duration_days": planning_context.trip.dates.duration_days,
            }
            yield f"data: {json.dumps(planning_status_event, ensure_ascii=False)}\n\n"

        # Event 3: Token streaming
        full_answer_parts = []
        try:
            for token in chain.stream_answer(
                question=user_question,
                standalone_question=standalone_question,
                chat_history=chat_history,
                planning_summary=planning_summary,
                mode=request.mode or "chat",
                location_context=location_context,
                weather_context=weather_context,
            ):
                full_answer_parts.append(token)
                yield f"data: {json.dumps({'type': 'token', 'token': token}, ensure_ascii=False)}\n\n"
        except Exception as e:
            logger.error("Streaming error: %s", e)
            yield f"data: {json.dumps({'type': 'error', 'message': 'Đã xảy ra lỗi khi tạo câu trả lời.'}, ensure_ascii=False)}\n\n"
            return

        final_answer = "".join(full_answer_parts).strip()

        # 5. Save AI message to database
        ai_msg = ConversationService.save_message(
            session=session,
            conversation_id=conversation.id,
            sender="AI",
            content=final_answer,
        )

        try:
            ConversationSummaryService.maybe_update_summary(
                session=session,
                conversation_id=conversation.id,
                user_id=conversation.user_id,
            )
        except ConversationSummaryError:
            logger.warning(
                "Conversation summary skipped after streaming response for conversation %s",
                conversation.id,
            )

        ConversationService.update_conversation_timestamp(session, conversation)

        # Event 4: Done
        done_payload = {
            "type": "done",
            "conversation_id": conversation.id,
            "message_id": ai_msg.id,
            "content": final_answer,
            "planning_status": planning_status,
            "is_ready_to_generate": is_ready,
            "planning_action": planning_action,
        }
        if planning_context:
            done_payload["planning_context"] = planning_context.model_dump()

        yield f"data: {json.dumps(done_payload, ensure_ascii=False)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
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
