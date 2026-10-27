"""Unit and integration tests for real-time conversation optimization, VAD interruption, and latency."""

from __future__ import annotations

import asyncio
import re
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# Ensure voice-agent root is on path
ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from livekit import rtc
from livekit.agents import vad
from livekit.plugins import silero

from coordinator import ConversationCoordinator, TurnMetrics
from agent import generate_test_tone_frames, speak_sentence


class TestTurnCoordinator(unittest.TestCase):
    """Test ConversationCoordinator turn lifecycle, metrics calculation, and cancellation."""

    def setUp(self):
        self.coordinator = ConversationCoordinator(conversation_id=42, user_id=101)

    def test_turn_creation_and_metrics_calculation(self):
        """Test accurate calculation of all 4 specified latency intervals."""
        turn_id = self.coordinator.start_new_turn("Đà Nẵng có gì chơi?")
        self.assertEqual(turn_id, 1)
        self.assertTrue(self.coordinator.is_turn_valid(turn_id))

        t0 = 100.0
        t1 = 100.450  # +450ms STT
        t2 = 101.250  # +800ms LLM
        t3 = 101.550  # +300ms TTS first audio
        t4 = 103.500  # TTS complete

        self.coordinator.record_user_speech_end(turn_id, timestamp=t0)
        self.coordinator.record_stt_done(turn_id, "Đà Nẵng có gì chơi?", timestamp=t1)
        self.coordinator.record_llm_first_chunk(turn_id, timestamp=t2)
        self.coordinator.record_tts_first_audio(turn_id, timestamp=t3)
        self.coordinator.record_tts_complete(turn_id, "Bạn có thể đi Bà Nà Hills", timestamp=t4)

        metrics = self.coordinator._current_metrics
        self.assertIsNotNone(metrics)

        # 1. Kết thúc giọng nói → STT hoàn thành
        self.assertAlmostEqual(metrics.speech_end_to_stt_ms, 450.0, places=1)
        # 2. STT hoàn thành → LLM bắt đầu trả kết quả
        self.assertAlmostEqual(metrics.stt_to_llm_ms, 800.0, places=1)
        # 3. LLM trả kết quả → TTS có audio đầu tiên
        self.assertAlmostEqual(metrics.llm_to_tts_first_audio_ms, 300.0, places=1)
        # 4. Kết thúc giọng nói → Người dùng nghe audio đầu tiên (E2E)
        self.assertAlmostEqual(metrics.speech_end_to_first_audio_ms, 1550.0, places=1)

        self.assertFalse(metrics.interrupted)
        self.assertFalse(self.coordinator.is_agent_speaking)

    def test_interruption_cancels_tasks_and_invalidates_turn(self):
        """Verify interruption stops speech in <10ms, cancels registered tasks, and invalidates turn."""
        turn_id = self.coordinator.start_new_turn("Kể về Hội An")
        self.coordinator.is_agent_speaking = True

        dummy_completed = False

        async def dummy_long_task():
            nonlocal dummy_completed
            try:
                await asyncio.sleep(5.0)
                dummy_completed = True
            except asyncio.CancelledError:
                pass

        async def run_test():
            task = asyncio.create_task(dummy_long_task())
            self.coordinator.register_task(task)

            # Trigger interruption
            cancel_duration_ms = self.coordinator.handle_interruption("User interrupted")
            await asyncio.sleep(0)  # Allow loop to deliver cancellation

            # Must cancel quickly (< 20ms)
            self.assertLess(cancel_duration_ms, 20.0)
            self.assertTrue(task.cancelled() or task.done())
            self.assertFalse(dummy_completed)
            self.assertFalse(self.coordinator.is_turn_valid(turn_id))
            self.assertFalse(self.coordinator.is_agent_speaking)
            self.assertTrue(self.coordinator._current_metrics.interrupted)

        asyncio.run(run_test())

    def test_context_preservation_across_cancelled_turns(self):
        """Verify conversation_id and user_id are never lost when a turn is interrupted."""
        self.assertEqual(self.coordinator.conversation_id, 42)
        self.assertEqual(self.coordinator.user_id, 101)

        # Turn 1 interrupted
        t1 = self.coordinator.start_new_turn("Câu hỏi 1")
        self.coordinator.is_agent_speaking = True
        self.coordinator.handle_interruption("Interrupted")

        self.assertFalse(self.coordinator.is_turn_valid(t1))
        self.assertEqual(self.coordinator.conversation_id, 42)  # Still preserved!

        # Turn 2 starts with same conversation_id
        t2 = self.coordinator.start_new_turn("Câu hỏi 2 thay thế")
        self.assertTrue(self.coordinator.is_turn_valid(t2))
        self.assertEqual(self.coordinator.conversation_id, 42)

        # Turn 2 updates conversation_id from backend response
        self.coordinator.update_conversation_id(88)
        self.assertEqual(self.coordinator.conversation_id, 88)


class TestStaleAudioRejection(unittest.TestCase):
    """Test that stale TTS frames are rejected instantaneously upon interruption."""

    def test_speak_sentence_stops_when_turn_invalidated(self):
        """Verify speak_sentence stops pushing audio frames as soon as turn is cancelled."""
        coordinator = ConversationCoordinator()
        turn_id = coordinator.start_new_turn("Test question")
        coordinator.is_agent_speaking = True

        mock_blaze_tts = MagicMock()
        mock_audio_source = MagicMock()
        mock_audio_source.capture_frame = AsyncMock()

        frames = generate_test_tone_frames(frequency=440.0, duration=0.4, sample_rate=24000)
        total_generated_frames = len(frames)  # 20 frames for 0.4s

        # Generator that yields frames and simulates interruption after frame 3
        async def fake_synthesize_stream(text):
            for i, f in enumerate(frames):
                if i == 3:
                    # User interrupts agent!
                    coordinator.handle_interruption("Simulated voice interrupt")
                ev = MagicMock()
                ev.frame = f
                yield ev

        mock_blaze_tts.synthesize = fake_synthesize_stream

        async def run():
            result = await speak_sentence(
                sentence="Đây là một câu trả lời dài thử nghiệm.",
                blaze_tts=mock_blaze_tts,
                audio_source=mock_audio_source,
                coordinator=coordinator,
                turn_id=turn_id,
            )
            return result

        success = asyncio.run(run())

        # speak_sentence should return False indicating interrupted
        self.assertFalse(success)
        # Should have captured only 3 frames, NOT all 20 frames!
        self.assertLessEqual(mock_audio_source.capture_frame.call_count, 4)
        self.assertLess(mock_audio_source.capture_frame.call_count, total_generated_frames)

    def test_e2e_interruption_and_follow_up_preserves_context(self):
        """Simulate Turn 1 interrupted mid-sentence followed by Turn 2.
        Verify no audio from Turn 1 leaks, cancellation takes <5ms, and context is preserved."""
        coordinator = ConversationCoordinator(conversation_id=99, user_id=101)
        mock_audio_source = MagicMock()
        mock_audio_source.capture_frame = AsyncMock()

        played_frames_turn_1 = []
        played_frames_turn_2 = []

        async def run_scenario():
            # --- Turn 1: User asks initial question ---
            t1 = coordinator.start_new_turn("Kể cho tôi về bán đảo Sơn Trà")
            coordinator.is_agent_speaking = True

            async def fake_tts_turn_1():
                for i in range(10):
                    if not coordinator.is_turn_valid(t1):
                        return
                    played_frames_turn_1.append(i)
                    await asyncio.sleep(0.01)

            t1_task = asyncio.create_task(fake_tts_turn_1())
            coordinator.register_task(t1_task)

            # Wait 25ms (plays ~2 frames)
            await asyncio.sleep(0.025)

            # User interrupts during Turn 1!
            t_interrupt_start = time.perf_counter()
            coordinator.handle_interruption("User interrupted with new question")
            t_interrupt_end = time.perf_counter()
            cancel_latency_ms = (t_interrupt_end - t_interrupt_start) * 1000

            # Wait for any potential leaks
            await asyncio.sleep(0.05)

            # Verify Turn 1 halted early
            self.assertLess(len(played_frames_turn_1), 10)
            self.assertFalse(coordinator.is_turn_valid(t1))
            self.assertLess(cancel_latency_ms, 5.0)  # Measured cancellation latency < 5ms

            # Context must still be preserved!
            self.assertEqual(coordinator.conversation_id, 99)

            # --- Turn 2: User asks follow-up question ---
            t2 = coordinator.start_new_turn("Đổi lại, Cầu Rồng phun lửa vào mấy giờ?")
            coordinator.is_agent_speaking = True

            async def fake_tts_turn_2():
                for i in range(5):
                    if not coordinator.is_turn_valid(t2):
                        return
                    played_frames_turn_2.append(i)
                    await asyncio.sleep(0.005)

            t2_task = asyncio.create_task(fake_tts_turn_2())
            coordinator.register_task(t2_task)

            await t2_task
            coordinator.record_tts_complete(t2, "Cầu Rồng phun lửa lúc 21h thứ bảy và chủ nhật.")

            # Turn 2 completes all 5 frames without interference
            self.assertEqual(len(played_frames_turn_2), 5)
            self.assertEqual(coordinator.conversation_id, 99)
            self.assertFalse(coordinator.is_agent_speaking)

        asyncio.run(run_scenario())


class TestSentenceTokenizer(unittest.TestCase):
    """Test streaming sentence segmentation to ensure no sentence clipping or out-of-order chunks."""

    def test_sentence_splitting_vietnamese(self):
        """Test splitting Vietnamese text stream into grammatical sentences without truncation."""
        delimiters = re.compile(r"([.!?\n]+(?:\s+|$))")
        text_stream = [
            "Đà ", "Nẵng có ", "nhiều địa ", "điểm đẹp. ",
            "Ví dụ ", "như Bán ", "đảo Sơn Trà, ", "Cầu Rồng! ",
            "Bạn có ", "muốn đi không?"
        ]

        buffer = ""
        sentences = []
        for token in text_stream:
            buffer += token
            parts = delimiters.split(buffer)
            if len(parts) > 1:
                sentence = (parts[0] + parts[1]).strip()
                buffer = "".join(parts[2:])
                if sentence:
                    sentences.append(sentence)

        if buffer.strip():
            sentences.append(buffer.strip())

        expected = [
            "Đà Nẵng có nhiều địa điểm đẹp.",
            "Ví dụ như Bán đảo Sơn Trà, Cầu Rồng!",
            "Bạn có muốn đi không?",
        ]
        self.assertEqual(sentences, expected)


class TestSileroVADParameters(unittest.TestCase):
    """Test Silero VAD loading with anti-false-interruption parameters."""

    def test_vad_initialization_parameters(self):
        """Verify Silero VAD is loaded with the required anti-noise configuration."""
        vad_model = silero.VAD.load(
            min_speech_duration=0.25,
            min_silence_duration=0.6,
            activation_threshold=0.55,
        )
        self.assertIsNotNone(vad_model)
        self.assertEqual(vad_model._opts.min_speech_duration, 0.25)
        self.assertEqual(vad_model._opts.min_silence_duration, 0.6)
        self.assertEqual(vad_model._opts.activation_threshold, 0.55)


if __name__ == "__main__":
    unittest.main()
