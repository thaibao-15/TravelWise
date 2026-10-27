"""Unit tests for Blaze AI STT and TTS LiveKit adapters."""

import asyncio
import json
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from livekit import rtc
from livekit.agents import APIConnectOptions, stt, tts

from blaze import (
    BlazeAuthError,
    BlazeChunkedStream,
    BlazeConnectionError,
    BlazeSpeechStream,
    BlazeSTT,
    BlazeSTTError,
    BlazeTimeoutError,
    BlazeTTS,
    BlazeTTSError,
)


class TestBlazeSTTAdapter(unittest.IsolatedAsyncioTestCase):
    """Test suite for BlazeSTT and BlazeSpeechStream."""

    def setUp(self):
        self.api_key = "test-blaze-stt-key-12345"
        self.adapter = BlazeSTT(
            api_key=self.api_key,
            ws_url="wss://api.blaze.vn/v1/stt/realtime",
            model="stt-stream-1.5",
            language="vi",
            sample_rate=16000,
        )

    def test_stt_initialization_and_properties(self):
        """Verify capabilities, audio sample rate, model, provider, and language."""
        self.assertEqual(self.adapter.provider, "blaze")
        self.assertEqual(self.adapter.model, "stt-stream-1.5")
        self.assertEqual(self.adapter.language, "vi")
        self.assertEqual(self.adapter.sample_rate, 16000)
        self.assertEqual(self.adapter.api_key, self.api_key)
        self.assertTrue(self.adapter.capabilities.streaming)
        self.assertTrue(self.adapter.capabilities.interim_results)

    async def test_stt_requires_api_key(self):
        """Verify error is raised when api_key is empty."""
        empty_adapter = BlazeSTT(api_key="")
        stream = empty_adapter.stream()
        try:
            with self.assertRaises(BlazeAuthError):
                await stream._run()
        finally:
            await stream.aclose()

    async def test_stt_handshake_and_interim_final_transcription(self):
        """Verify successful WebSocket handshake and parsing of interim & final transcripts."""
        # Messages yielded during _recv_loop
        recv_messages = [
            json.dumps({"type": "partial", "text": "xin chào", "is_final": False}),
            json.dumps({"type": "final", "text": "xin chào du lịch đà nẵng", "is_final": True}),
        ]

        class MockWebSocket:
            def __aiter__(self):
                return self

            async def __anext__(self):
                if recv_messages:
                    return recv_messages.pop(0)
                raise StopAsyncIteration

        mock_ws = MockWebSocket()
        stream = self.adapter.stream()

        # Run _recv_loop
        await stream._recv_loop(mock_ws)

        # Collect emitted events from stream iterator
        events = []
        while not stream._event_ch.empty():
            events.append(stream._event_ch.recv_nowait())

        self.assertEqual(len(events), 2)

        # 1st event: interim transcript
        self.assertEqual(events[0].type, stt.SpeechEventType.INTERIM_TRANSCRIPT)
        self.assertEqual(events[0].alternatives[0].text, "xin chào")
        self.assertEqual(events[0].alternatives[0].language, "vi")

        # 2nd event: final transcript
        self.assertEqual(events[1].type, stt.SpeechEventType.FINAL_TRANSCRIPT)
        self.assertEqual(events[1].alternatives[0].text, "xin chào du lịch đà nẵng")
        self.assertEqual(events[1].alternatives[0].language, "vi")


    async def test_stt_provider_error_handling(self):
        """Verify provider error frame raises BlazeSTTError."""
        mock_ws = AsyncMock()

        async def mock_aiter():
            yield json.dumps({"type": "error", "message": "Quá tải máy chủ nhận diện giọng nói"})

        mock_ws.__aiter__ = lambda self: mock_aiter()

        stream = self.adapter.stream()
        with self.assertRaises(BlazeSTTError) as ctx:
            await stream._recv_loop(mock_ws)

        self.assertIn("Quá tải máy chủ", str(ctx.exception))

    async def test_stt_audio_frame_streaming(self):
        """Verify PCM audio frames are extracted and sent as bytes to WebSocket."""
        mock_ws = AsyncMock()
        mock_ws.send = AsyncMock()

        stream = self.adapter.stream()

        # Push 2 test PCM frames (16kHz mono, 160 samples = 320 bytes per frame)
        pcm_bytes = b"\x00\x01" * 160
        frame1 = rtc.AudioFrame(data=pcm_bytes, sample_rate=16000, num_channels=1, samples_per_channel=160)
        frame2 = rtc.AudioFrame(data=pcm_bytes, sample_rate=16000, num_channels=1, samples_per_channel=160)

        stream._input_ch.send_nowait(frame1)
        stream._input_ch.send_nowait(frame2)
        stream._input_ch.close()

        await stream._send_loop(mock_ws)

        self.assertEqual(mock_ws.send.call_count, 2)
        for call_arg in mock_ws.send.call_args_list:
            self.assertEqual(call_arg[0][0], pcm_bytes)


class TestBlazeTTSAdapter(unittest.IsolatedAsyncioTestCase):
    """Test suite for BlazeTTS and BlazeChunkedStream."""

    def setUp(self):
        self.api_key = "test-blaze-tts-key-67890"
        self.adapter = BlazeTTS(
            api_key=self.api_key,
            ws_url="wss://api.blaze.vn/v1/tts/realtime",
            speaker_id="DaNang-Nu-1-BL",
            model="2.0-realtime",
            speed="1.5",
            audio_format="mp3",
            audio_quality=64,
            sample_rate=24000,
            num_channels=1,
        )

    def test_tts_initialization_and_properties(self):
        """Verify audio format, model, speaker, sample rate, and channels."""
        self.assertEqual(self.adapter.provider, "blaze")
        self.assertEqual(self.adapter.model, "2.0-realtime")
        self.assertEqual(self.adapter.speaker_id, "DaNang-Nu-1-BL")
        self.assertEqual(self.adapter.speed, "1.5")
        self.assertEqual(self.adapter.audio_format, "mp3")
        self.assertEqual(self.adapter.audio_quality, 64)
        self.assertEqual(self.adapter.sample_rate, 24000)
        self.assertEqual(self.adapter.num_channels, 1)

    async def test_tts_empty_input_handled_gracefully(self):
        """Verify empty or whitespace-only text returns without error."""
        chunked_stream = self.adapter.synthesize("   ")
        mock_emitter = MagicMock()
        try:
            await chunked_stream._run(mock_emitter)
            mock_emitter.initialize.assert_not_called()
        finally:
            await chunked_stream.aclose()

    async def test_tts_requires_api_key(self):
        """Verify error is raised when api_key is empty."""
        empty_adapter = BlazeTTS(api_key="")
        chunked_stream = empty_adapter.synthesize("Xin chào")
        mock_emitter = MagicMock()
        try:
            with self.assertRaises(BlazeAuthError):
                await chunked_stream._run(mock_emitter)
        finally:
            await chunked_stream.aclose()

    @patch("websockets.connect")
    async def test_tts_streaming_synthesis_flow(self, mock_connect):
        """Verify auth + query frames sent and binary MP3 chunks pushed to AudioEmitter."""
        mock_ws = AsyncMock()
        mock_connect.return_value.__aenter__.return_value = mock_ws

        # Server sends 2 binary MP3 audio chunks followed by finished-byte-stream
        fake_mp3_chunk1 = b"\xff\xfb\x90\x00" + b"\x00" * 100
        fake_mp3_chunk2 = b"\xff\xfb\x90\x00" + b"\x00" * 150
        finished_frame = json.dumps({"type": "finished-byte-stream"})

        mock_ws.recv = AsyncMock(side_effect=[
            fake_mp3_chunk1,
            fake_mp3_chunk2,
            finished_frame,
        ])

        chunked_stream = self.adapter.synthesize("Chào mừng đến với TravelWise.")
        mock_emitter = MagicMock()

        await chunked_stream._run(mock_emitter)

        # Check AudioEmitter was initialized with MP3 mime_type
        mock_emitter.initialize.assert_called_once()
        init_kwargs = mock_emitter.initialize.call_args[1]
        self.assertEqual(init_kwargs["sample_rate"], 24000)
        self.assertEqual(init_kwargs["num_channels"], 1)
        self.assertEqual(init_kwargs["mime_type"], "audio/mp3")

        # Check WebSocket messages sent (auth + query)
        self.assertEqual(mock_ws.send.call_count, 2)
        auth_sent = json.loads(mock_ws.send.call_args_list[0][0][0])
        self.assertEqual(auth_sent["token"], self.api_key)
        self.assertEqual(auth_sent["strategy"], "request")

        query_sent = json.loads(mock_ws.send.call_args_list[1][0][0])
        self.assertEqual(query_sent["query"], "Chào mừng đến với TravelWise.")
        self.assertEqual(query_sent["speaker_id"], "DaNang-Nu-1-BL")
        self.assertEqual(query_sent["audio_speed"], "1.5")
        self.assertEqual(query_sent["audio_format"], "mp3")


        # Check chunks pushed to emitter
        self.assertEqual(mock_emitter.push.call_count, 2)
        mock_emitter.push.assert_any_call(fake_mp3_chunk1)
        mock_emitter.push.assert_any_call(fake_mp3_chunk2)

    @patch("websockets.connect")
    async def test_tts_provider_error_handling(self, mock_connect):
        """Verify provider error frame raises BlazeTTSError."""
        mock_ws = AsyncMock()
        mock_connect.return_value.__aenter__.return_value = mock_ws

        mock_ws.recv = AsyncMock(return_value=json.dumps({
            "type": "error",
            "message": "Giọng đọc DaNang-Nu-1-BL tạm thời không khả dụng",
        }))

        chunked_stream = self.adapter.synthesize("Kiểm tra lỗi.")
        mock_emitter = MagicMock()

        with self.assertRaises(BlazeTTSError) as ctx:
            await chunked_stream._run(mock_emitter)

        self.assertIn("không khả dụng", str(ctx.exception))

    @patch("websockets.connect")
    async def test_tts_cancellation_handling(self, mock_connect):
        """Verify cancellation during synthesis terminates cleanly."""
        mock_ws = AsyncMock()
        mock_connect.return_value.__aenter__.return_value = mock_ws

        async def slow_recv():
            await asyncio.sleep(10.0)
            return b"data"

        mock_ws.recv = slow_recv

        chunked_stream = self.adapter.synthesize("Nội dung dài đang đọc...")
        mock_emitter = MagicMock()

        task = asyncio.create_task(chunked_stream._run(mock_emitter))
        await asyncio.sleep(0.05)
        task.cancel()

        with self.assertRaises(asyncio.CancelledError):
            await task


if __name__ == "__main__":
    unittest.main()
