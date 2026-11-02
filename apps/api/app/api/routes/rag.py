
import json
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
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


def get_planning_signals(user_question, planning_context):
    """Extract trip planning status and requested action."""
    planning_status = None
    is_ready_to_generate = None
    planning_action = None

    if not planning_context:
        return planning_status, is_ready_to_generate, planning_action

    if isinstance(planning_context, dict):
        planning_state = planning_context.get("planning_state") or {}
        if isinstance(planning_state, dict):
            is_ready = bool(planning_state.get("is_ready_to_generate"))
        else:
            is_ready = bool(
                getattr(planning_state, "is_ready_to_generate", False)
            )
    else:
        planning_state = getattr(planning_context, "planning_state", None)
        is_ready = bool(
            planning_state
            and getattr(planning_state, "is_ready_to_generate", False)
        )

    is_ready_to_generate = is_ready
    planning_status = (
        "ready_to_generate"
        if is_ready
        else "collecting_requirements"
    )

    user_lower = user_question.lower()

    if any(kw in user_lower for kw in [
        "tạo lịch trình",
        "lên lịch trình",
        "tạo ngay",
        "tạo cho tôi",
        "generate itinerary",
    ]):
        if is_ready:
            planning_action = "TRIGGER_GENERATION"

    elif any(kw in user_lower for kw in [
        "lưu lịch trình",
        "lưu chuyến đi",
        "save trip",
        "lưu ngay",
    ]):
        planning_action = "TRIGGER_SAVE"

    elif any(kw in user_lower for kw in [
        "chỉnh sửa lịch trình",
        "sửa lịch trình",
        "đổi điểm",
        "thay đổi lịch trình",
        "thêm vào lịch trình",
        "xóa khỏi lịch trình",
        "đổi khách sạn",
    ]):
        planning_action = "TRIGGER_EDIT"

    return planning_status, is_ready_to_generate, planning_action


def suggest_media_safely(session, question):
    """Suggest images/videos without interrupting chat."""
    try:
        from app.services.media_service import MediaService

        return MediaService.suggest_media_for_query(session, question)
    except Exception as exc:
        logger.debug("Media suggestion error: %s", exc)
        return None


@router.post(
    "/search",
    response_model=RAGSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Semantic Search Knowledge",
    description=(
        "Tìm kiếm các đoạn knowledge liên quan nhất "
        "dựa trên semantic similarity search qua Chroma vector store."
    ),
)
def search_knowledge(request: RAGSearchRequest) -> RAGSearchResponse:
    """Execute semantic search against TravelWise knowledge."""
    retriever = RAGRetriever()
    results = retriever.search(
        query=request.query,
        top_k=request.top_k,
    )

    return RAGSearchResponse(
        query=request.query,
        results=results,
    )


@router.post(
    "/ask",
    response_model=RAGAskResponse,
    status_code=status.HTTP_200_OK,
    summary="Ask TravelWise RAG with Memory",
    description=(
        "Hỏi đáp du lịch thông minh dựa trên cơ sở "
        "tri thức RAG và Conversation Memory."
    ),
)
def ask_knowledge(
    request: RAGAskRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> RAGAskResponse:

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
        title = user_question[:60] + (
            "..." if len(user_question) > 60 else ""
        )
        user_id = current_user.id if current_user else None

        conversation = ConversationService.create_conversation(
            session=session,
            user_id=user_id,
            title=title,
        )

    # 2. Save user message
    user_msg = ConversationService.save_message(
        session=session,
        conversation_id=conversation.id,
        sender="USER",
        content=user_question,
    )

    # 3. Extract trip planning context
    planning_context = None

    try:
        from app.services.trip_planning_service import (
            TripPlanningContextExtractionService,
        )

        planning_context = (
            TripPlanningContextExtractionService
            .extract_and_update_trip_context(
                session=session,
                conversation_id=conversation.id,
                current_user=current_user,
                latest_message=user_msg,
            )
        )
    except Exception as exc:
        logger.error(
            "Planning context extraction error for conversation %s: %s",
            conversation.id,
            exc,
        )

    # 4. Load conversation memory
    try:
        current_summary = ConversationSummaryService.get_summary(
            session=session,
            conversation_id=conversation.id,
            user_id=conversation.user_id,
        )

        previous_summaries = (
            ConversationSummaryService.get_recent_user_summaries(
                session=session,
                user_id=conversation.user_id,
                exclude_conversation_id=conversation.id,
            )
        )
    except SQLAlchemyError as exc:
        logger.warning(
            "Conversation summary unavailable for %s: %s",
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
            continue

        if msg.sender == "USER":
            chat_history.append(HumanMessage(content=msg.content))
        elif msg.sender == "AI":
            chat_history.append(AIMessage(content=msg.content))

    # 5. Invoke RAG chain
    try:
        chain = get_rag_chain()

        standalone_question = chain.contextualize_question(
            question=user_question,
            chat_history=chat_history,
        )

        planning_summary = ""

        if planning_context:
            planning_summary = (
                TripPlanningContextExtractionService
                .format_context_summary(planning_context)
            )

        weather_question = (
            standalone_question
            if isinstance(standalone_question, str)
            else user_question
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
            image_urls=request.image_urls,
        )

        answer = result["answer"]

    except RAGChainError as exc:
        logger.error("RAG chain error: %s", exc.message)

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.",
        )

    except HTTPException:
        raise

    except Exception as exc:
        logger.error(
            "Unexpected error in /rag/ask: %s",
            type(exc).__name__,
        )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Đã xảy ra lỗi nội bộ khi xử lý câu hỏi.",
        )

    # 6. Save AI response
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
            "Conversation summary skipped for %s",
            conversation.id,
        )

    ConversationService.update_conversation_timestamp(
        session,
        conversation,
    )

    # 7. Image/video suggestions
    suggested_media = suggest_media_safely(
        session,
        user_question,
    )

    # 8. Trip planning signals
    (
        planning_status,
        is_ready_to_generate,
        planning_action,
    ) = get_planning_signals(
        user_question,
        planning_context,
    )

    # 9. Combined response
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
        media=suggested_media if suggested_media else None,
        planning_status=planning_status,
        is_ready_to_generate=is_ready_to_generate,
        planning_action=planning_action,
    )


@router.post(
    "/ask-stream",
    summary="Hỏi đáp AI có phản hồi thời gian thực qua Streaming (SSE)",
    description=(
        "Stream trực tiếp từng token từ LLM qua Server-Sent Events "
        "giúp giảm tối đa độ trễ phản hồi cho người dùng."
    ),
)
async def ask_rag_stream(
    request: RAGAskRequest,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
):

    user_question = request.get_question()

    location_context = (
        f"Vĩ độ: {request.current_location.latitude:.6f}, "
        f"Kinh độ: {request.current_location.longitude:.6f}. "
        "Hãy dùng vị trí này làm vị trí hiện tại của người dùng; "
        "không suy đoán địa chỉ cụ thể nếu không có dữ liệu bản đồ xác nhận."
        if request.current_location
        else None
    )

    # 1. Resolve conversation
    if request.conversation_id is not None:
        conversation = ConversationService.get_conversation_by_id(
            session=session,
            conversation_id=request.conversation_id,
            current_user=current_user,
            check_ownership=True,
        )
    else:
        title = user_question[:60] + (
            "..." if len(user_question) > 60 else ""
        )

        user_id = current_user.id if current_user else None

        conversation = ConversationService.create_conversation(
            session=session,
            user_id=user_id,
            title=title,
        )

    # 2. Load memory
    try:
        current_summary = ConversationSummaryService.get_summary(
            session=session,
            conversation_id=conversation.id,
            user_id=conversation.user_id,
        )

        previous_summaries = (
            ConversationSummaryService.get_recent_user_summaries(
                session=session,
                user_id=conversation.user_id,
                exclude_conversation_id=conversation.id,
            )
        )

    except SQLAlchemyError as exc:
        logger.warning(
            "Conversation summary unavailable for streaming %s: %s",
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
        if msg.sender == "USER":
            chat_history.append(HumanMessage(content=msg.content))
        elif msg.sender == "AI":
            chat_history.append(AIMessage(content=msg.content))

    # 3. Prepare RAG chain
    chain = get_rag_chain()

    # Voice mode optimization
    if request.mode == "voice":
        standalone_question = user_question
    else:
        standalone_question = chain.contextualize_question(
            question=user_question,
            chat_history=chat_history,
        )

    # 4. Load existing trip planning context
    planning_summary = ""

    try:
        from app.services.trip_planning_service import (
            TripPlanningContextExtractionService,
        )

        existing_ctx = (
            TripPlanningContextExtractionService
            .get_planning_context_by_conversation(
                session=session,
                conversation_id=conversation.id,
                current_user=current_user,
                check_ownership=False,
            )
        )

        if existing_ctx:
            planning_summary = (
                TripPlanningContextExtractionService
                .format_context_summary(existing_ctx)
            )

    except Exception as exc:
        logger.debug(
            "Could not retrieve planning context: %s",
            exc,
        )

    # 5. Weather context
    weather_question = (
        standalone_question
        if isinstance(standalone_question, str)
        else user_question
    )

    weather_context = await WeatherContextService.build_context(
        session=session,
        question=weather_question,
        current_location=request.current_location,
    )

    # 6. Stream response
    async def event_generator():

        yield (
            f"data: {json.dumps({'type': 'init', 'conversation_id': conversation.id})}\n\n"
        )

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
                image_urls=request.image_urls,
            ):
                full_answer_parts.append(token)

                yield (
                    f"data: {json.dumps({'type': 'token', 'token': token})}\n\n"
                )

        except Exception as exc:
            logger.error("Streaming error: %s", exc)

            yield (
                f"data: {json.dumps({'type': 'error', 'message': 'Đã xảy ra lỗi khi tạo câu trả lời.'})}\n\n"
            )
            return

        final_answer = "".join(full_answer_parts).strip()

        # 7. Save user message
        user_msg = ConversationService.save_message(
            session=session,
            conversation_id=conversation.id,
            sender="USER",
            content=user_question,
        )

        # 8. Extract updated planning context
        planning_context_data = None

        try:
            from app.services.trip_planning_service import (
                TripPlanningContextExtractionService,
            )

            ctx = (
                TripPlanningContextExtractionService
                .extract_and_update_trip_context(
                    session=session,
                    conversation_id=conversation.id,
                    current_user=current_user,
                    latest_message=user_msg,
                )
            )

            if ctx:
                planning_context_data = ctx.model_dump()

        except Exception as exc:
            logger.error(
                "Planning context extraction error in stream: %s",
                exc,
            )

        # 9. Save AI message
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
                "Conversation summary skipped after streaming for %s",
                conversation.id,
            )

        # 10. Image/video suggestions
        suggested_media = suggest_media_safely(
            session,
            user_question,
        )

        if suggested_media:
            media_payload = {
                "type": "media",
                "media": [
                    m.model_dump()
                    for m in suggested_media
                ],
            }

            yield (
                f"data: {json.dumps(media_payload)}\n\n"
            )

        # 11. Final SSE payload
        done_payload = {
            "type": "done",
            "conversation_id": conversation.id,
            "message_id": ai_msg.id,
            "content": final_answer,
        }

        if planning_context_data:
            done_payload["planning_context"] = planning_context_data

            (
                planning_status,
                is_ready_to_generate,
                planning_action,
            ) = get_planning_signals(
                user_question,
                planning_context_data,
            )

            done_payload["planning_status"] = planning_status
            done_payload["is_ready_to_generate"] = (
                is_ready_to_generate
            )

            if planning_action:
                done_payload["planning_action"] = planning_action

        if suggested_media:
            done_payload["media"] = [
                m.model_dump()
                for m in suggested_media
            ]

        yield (
            f"data: {json.dumps(done_payload)}\n\n"
        )

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
    description=(
        "Kiểm tra kết nối trực tiếp từ FastAPI tới Chat Model "
        "(Gemini / OpenAI). Không expose API key."
    ),
)
def test_llm_connection(
    request: LLMTestRequest,
) -> LLMTestResponse:

    try:
        llm = get_chat_llm()

        response = llm.invoke(request.prompt)

        response_text = extract_response_text(
            getattr(response, "content", response)
        )

        provider = (
            settings.LLM_PROVIDER or "gemini"
        ).lower()

        active_model = (
            settings.GEMINI_MODEL
            if provider == "gemini"
            else settings.OPENAI_MODEL
        )

        return LLMTestResponse(
            status="success",
            provider=provider,
            model=active_model,
            response=response_text,
        )

    except ValueError as exc:
        logger.warning(
            "LLM configuration error during test: %s",
            type(exc).__name__,
        )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )

    except Exception as exc:
        logger.error(
            "LLM execution error during test: %s",
            type(exc).__name__,
        )

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to communicate with LLM service.",
        )
