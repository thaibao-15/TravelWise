"""Real-time conversation turn coordinator, VAD interruption, and latency tracker."""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Any, List, Optional

logger = logging.getLogger("travelwise.coordinator")


@dataclass
class TurnMetrics:
    """Detailed timing metrics for a single conversational turn."""

    turn_id: int
    user_speech_end_time: Optional[float] = None
    stt_done_time: Optional[float] = None
    llm_first_chunk_time: Optional[float] = None
    tts_first_audio_time: Optional[float] = None
    tts_complete_time: Optional[float] = None
    interrupted: bool = False
    question_text: str = ""
    answer_text: str = ""

    @property
    def speech_end_to_stt_ms(self) -> Optional[float]:
        if self.user_speech_end_time and self.stt_done_time:
            return max(0.0, (self.stt_done_time - self.user_speech_end_time) * 1000)
        return None

    @property
    def stt_to_llm_ms(self) -> Optional[float]:
        if self.stt_done_time and self.llm_first_chunk_time:
            return max(0.0, (self.llm_first_chunk_time - self.stt_done_time) * 1000)
        return None

    @property
    def llm_to_tts_first_audio_ms(self) -> Optional[float]:
        if self.llm_first_chunk_time and self.tts_first_audio_time:
            return max(0.0, (self.tts_first_audio_time - self.llm_first_chunk_time) * 1000)
        return None

    @property
    def speech_end_to_first_audio_ms(self) -> Optional[float]:
        """Total End-to-End latency: User finished speaking to first audio byte emitted."""
        if self.user_speech_end_time and self.tts_first_audio_time:
            return max(0.0, (self.tts_first_audio_time - self.user_speech_end_time) * 1000)
        return None


class ConversationCoordinator:
    """Coordinates turn lifecycle, interruption handling, VAD events, and context preservation."""

    def __init__(
        self,
        conversation_id: Optional[int] = None,
        user_id: Optional[int] = None,
    ) -> None:
        self.conversation_id: Optional[int] = conversation_id
        self.user_id: Optional[int] = user_id

        self.current_turn_id: int = 0
        self.is_agent_speaking: bool = False

        self._active_tasks: List[asyncio.Task] = []
        self._interruption_event = asyncio.Event()

        self.metrics_history: List[TurnMetrics] = []
        self._current_metrics: Optional[TurnMetrics] = None

        self._lock = asyncio.Lock()

    def start_new_turn(self, question: str = "") -> int:
        """Start a new turn, advancing turn_id so previous in-flight tasks are discarded."""
        self.current_turn_id += 1
        turn_id = self.current_turn_id

        metrics = TurnMetrics(turn_id=turn_id, question_text=question)
        self._current_metrics = metrics
        self.metrics_history.append(metrics)

        self._interruption_event.clear()
        logger.debug("Turn %d started: '%s'", turn_id, question[:50])
        return turn_id

    def record_user_speech_end(self, turn_id: int, timestamp: Optional[float] = None) -> None:
        """Record the precise moment VAD detected the user finished speaking."""
        ts = timestamp or time.perf_counter()
        if self._current_metrics and self._current_metrics.turn_id == turn_id:
            self._current_metrics.user_speech_end_time = ts

    def record_stt_done(self, turn_id: int, question: str, timestamp: Optional[float] = None) -> None:
        """Record the moment STT finalized the transcript."""
        ts = timestamp or time.perf_counter()
        if self._current_metrics and self._current_metrics.turn_id == turn_id:
            self._current_metrics.stt_done_time = ts
            self._current_metrics.question_text = question
            if not self._current_metrics.user_speech_end_time:
                # If VAD did not record an earlier boundary, anchor to STT done time minus small offset
                self._current_metrics.user_speech_end_time = ts

    def record_llm_first_chunk(self, turn_id: int, timestamp: Optional[float] = None) -> None:
        """Record the moment LLM/RAG yielded the first token or sentence."""
        ts = timestamp or time.perf_counter()
        if self._current_metrics and self._current_metrics.turn_id == turn_id:
            if not self._current_metrics.llm_first_chunk_time:
                self._current_metrics.llm_first_chunk_time = ts

    def record_tts_first_audio(self, turn_id: int, timestamp: Optional[float] = None) -> None:
        """Record the moment the first PCM audio frame was pushed to WebRTC."""
        ts = timestamp or time.perf_counter()
        if self._current_metrics and self._current_metrics.turn_id == turn_id:
            if not self._current_metrics.tts_first_audio_time:
                self._current_metrics.tts_first_audio_time = ts
                self.is_agent_speaking = True
                self._log_turn_latency(self._current_metrics)

    def record_tts_complete(self, turn_id: int, answer: str, timestamp: Optional[float] = None) -> None:
        """Record speech completion for this turn."""
        ts = timestamp or time.perf_counter()
        if self._current_metrics and self._current_metrics.turn_id == turn_id:
            self._current_metrics.tts_complete_time = ts
            self._current_metrics.answer_text = answer
        self.is_agent_speaking = False

    def is_turn_valid(self, turn_id: int) -> bool:
        """Check if turn_id is still current (has not been superseded by an interruption)."""
        return turn_id == self.current_turn_id and not self._interruption_event.is_set()

    def handle_interruption(self, reason: str = "User voice detected") -> float:
        """Execute instantaneous cancellation of active speech & LLM tasks.

        Returns:
            Cancellation duration in milliseconds.
        """
        start = time.perf_counter()
        old_turn_id = self.current_turn_id

        # Mark current turn as interrupted
        if self._current_metrics:
            self._current_metrics.interrupted = True

        # Signal cancellation event
        self._interruption_event.set()
        self.is_agent_speaking = False

        # Advance turn_id immediately so any ongoing callbacks discard frames
        self.current_turn_id += 1

        # Cancel all registered tasks
        cancelled_count = 0
        for task in self._active_tasks:
            if not task.done():
                task.cancel()
                cancelled_count += 1
        self._active_tasks.clear()

        cancellation_duration_ms = (time.perf_counter() - start) * 1000
        logger.info(
            "🛑 [Interruption Confirmed] Đã hủy lượt %d trong %.2fms (%d tasks bị dừng, lý do: %s). Context được bảo toàn: conv_id=%s",
            old_turn_id,
            cancellation_duration_ms,
            cancelled_count,
            reason,
            self.conversation_id,
        )
        return cancellation_duration_ms

    def register_task(self, task: asyncio.Task) -> None:
        """Register a background Task to be cancelled upon interruption."""
        self._active_tasks.append(task)
        task.add_done_callback(lambda t: self._active_tasks.remove(t) if t in self._active_tasks else None)

    def update_conversation_id(self, conv_id: Optional[int]) -> None:
        """Update conversation_id without losing context."""
        if conv_id is not None:
            self.conversation_id = conv_id

    def _log_turn_latency(self, m: TurnMetrics) -> None:
        """Print latency breakdown according to user specifications."""
        stt_ms = m.speech_end_to_stt_ms
        llm_ms = m.stt_to_llm_ms
        tts_ms = m.llm_to_tts_first_audio_ms
        e2e_ms = m.speech_end_to_first_audio_ms

        logger.info("=================================================================")
        logger.info("⏱️ [BÁO CÁO ĐỘ TRỄ LƯỢT %d]", m.turn_id)
        if stt_ms is not None:
            logger.info("  1. Kết thúc giọng nói → STT hoàn thành: %.1fms", stt_ms)
        if llm_ms is not None:
            logger.info("  2. STT hoàn thành → LLM bắt đầu trả kết quả: %.1fms", llm_ms)
        if tts_ms is not None:
            logger.info("  3. LLM trả kết quả → TTS có audio đầu tiên: %.1fms", tts_ms)
        if e2e_ms is not None:
            logger.info("  🎯 4. Kết thúc giọng nói → Người dùng nghe audio đầu tiên: %.1fms", e2e_ms)
        logger.info("=================================================================")
