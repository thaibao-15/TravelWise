"""Client to invoke existing TravelWise FastAPI RAG and Gemini services."""

from __future__ import annotations

import json
import logging
import time
from typing import Any, AsyncGenerator, Dict, Optional

import httpx
import jwt

from config import config

logger = logging.getLogger("travelwise.rag-client")


class RAGClientError(Exception):
    """Exception raised when calling internal TravelWise RAG API fails."""

    def __init__(self, message: str, status_code: int = 500) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class TravelWiseRAGClient:
    """HTTP client to query the existing TravelWise Gemini + Chroma RAG pipeline."""

    def __init__(
        self,
        base_url: Optional[str] = None,
        jwt_secret: Optional[str] = None,
        jwt_algorithm: Optional[str] = None,
    ) -> None:
        self.base_url = (base_url or config.BACKEND_API_URL).rstrip("/")
        self.jwt_secret = jwt_secret or config.JWT_SECRET
        self.jwt_algorithm = jwt_algorithm or config.JWT_ALGORITHM

    def generate_auth_token(self, user_id: int) -> str:
        """Create a short-lived internal JWT token to authenticate as user_id."""
        payload = {
            "sub": str(user_id),
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
        }
        return jwt.encode(payload, self.jwt_secret, algorithm=self.jwt_algorithm)

    def _build_headers(self, user_id: Optional[int] = None) -> Dict[str, str]:
        """Construct request headers including optional Bearer token."""
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        if user_id is not None:
            token = self.generate_auth_token(user_id)
            headers["Authorization"] = f"Bearer {token}"
        return headers

    async def ask(
        self,
        question: str,
        conversation_id: Optional[int] = None,
        user_id: Optional[int] = None,
        current_location: Optional[Dict[str, float]] = None,
        mode: str = "voice",
        timeout: float = 25.0,
    ) -> Dict[str, Any]:
        """Call /api/v1/rag/ask to get a conversational RAG response with memory."""
        clean_question = (question or "").strip()
        if not clean_question:
            return {
                "answer": "Vui lòng đặt câu hỏi để TravelWise có thể hỗ trợ bạn.",
                "conversation_id": conversation_id,
                "message_id": None,
                "planning_context": None,
                "duration_ms": 0.0,
            }

        endpoint = f"{self.base_url}/api/v1/rag/ask"
        headers = self._build_headers(user_id=user_id)
        payload = {
            "query": clean_question,
            "conversation_id": conversation_id,
            "mode": mode,
            "current_location": current_location,
        }

        start_time = time.perf_counter()
        logger.info(
            "🧠 [RAG Ask] Gửi câu hỏi đến FastAPI RAG: '%s' (conv_id=%s, user_id=%s, mode=%s)",
            clean_question,
            conversation_id,
            user_id,
            mode,
        )

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(endpoint, json=payload, headers=headers)

            duration_ms = (time.perf_counter() - start_time) * 1000

            if response.status_code != 200:
                err_text = response.text
                logger.error("Lỗi từ RAG API (HTTP %d): %s", response.status_code, err_text)
                raise RAGClientError(
                    f"RAG API returned status {response.status_code}: {err_text}",
                    status_code=response.status_code,
                )

            data = response.json()
            message_obj = data.get("message", {})
            answer = message_obj.get("content", "").strip()
            returned_conv_id = data.get("conversation_id", conversation_id)
            planning_context = data.get("planning_context")

            logger.info(
                "✅ [RAG Ask Success] Nhận phản hồi trong %.1fms (conv_id=%s, độ dài=%d ký tự): '%s...'",
                duration_ms,
                returned_conv_id,
                len(answer),
                answer[:60],
            )

            return {
                "answer": answer,
                "conversation_id": returned_conv_id,
                "message_id": message_obj.get("id"),
                "planning_context": planning_context,
                "duration_ms": duration_ms,
            }

        except httpx.TimeoutException as exc:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.error("Quá thời gian chờ (%.1fms) từ RAG API: %s", duration_ms, exc)
            raise RAGClientError("Quá thời gian chờ phản hồi từ hệ thống RAG.", status_code=504) from exc
        except httpx.RequestError as exc:
            duration_ms = (time.perf_counter() - start_time) * 1000
            logger.error("Không thể kết nối đến RAG API (%.1fms): %s", duration_ms, exc)
            raise RAGClientError(f"Không thể kết nối đến máy chủ RAG: {exc}", status_code=503) from exc

    async def ask_stream(
        self,
        question: str,
        conversation_id: Optional[int] = None,
        user_id: Optional[int] = None,
        current_location: Optional[Dict[str, float]] = None,
        mode: str = "voice",
        timeout: float = 30.0,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """Stream response tokens via SSE from /api/v1/rag/ask-stream."""
        clean_question = (question or "").strip()
        if not clean_question:
            yield {"type": "token", "token": "Vui lòng đặt câu hỏi để TravelWise hỗ trợ bạn."}
            yield {"type": "done", "content": "Vui lòng đặt câu hỏi để TravelWise hỗ trợ bạn."}
            return

        endpoint = f"{self.base_url}/api/v1/rag/ask-stream"
        headers = self._build_headers(user_id=user_id)
        headers["Accept"] = "text/event-stream"
        payload = {
            "query": clean_question,
            "conversation_id": conversation_id,
            "mode": mode,
            "current_location": current_location,
        }

        start_time = time.perf_counter()
        first_token_time = None

        logger.info(
            "🧠 [RAG Stream] Bắt đầu stream câu hỏi: '%s' (conv_id=%s, user_id=%s)",
            clean_question,
            conversation_id,
            user_id,
        )

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                async with client.stream("POST", endpoint, json=payload, headers=headers) as response:
                    if response.status_code != 200:
                        err_text = await response.aread()
                        logger.error("Lỗi từ RAG stream (HTTP %d): %s", response.status_code, err_text.decode("utf-8", "ignore"))
                        raise RAGClientError(f"RAG stream returned HTTP {response.status_code}", status_code=response.status_code)

                    async for line in response.aiter_lines():
                        if not line or not line.startswith("data: "):
                            continue

                        data_str = line[len("data: "):].strip()
                        if not data_str:
                            continue

                        try:
                            event_data = json.loads(data_str)
                        except Exception:
                            continue

                        ev_type = event_data.get("type")
                        if ev_type == "token":
                            if first_token_time is None:
                                first_token_time = time.perf_counter()
                                ttft_ms = (first_token_time - start_time) * 1000
                                logger.info("⚡ [RAG TTFT] Time to first token: %.1fms", ttft_ms)

                        yield event_data

            total_ms = (time.perf_counter() - start_time) * 1000
            logger.info("🏁 [RAG Stream Done] Hoàn tất stream trong %.1fms", total_ms)

        except (httpx.TimeoutException, httpx.RequestError) as exc:
            logger.error("Lỗi kết nối RAG stream: %s", exc)
            yield {"type": "error", "message": "Lỗi kết nối đến dịch vụ RAG."}
