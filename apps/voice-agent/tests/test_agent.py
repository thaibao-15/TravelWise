import unittest
from unittest.mock import patch

from livekit import rtc
from livekit.agents import WorkerOptions

from agent import entrypoint, generate_test_tone_frames
from config import AgentConfig


class TestVoiceAgentUnit(unittest.TestCase):
    """Unit tests for TravelWise LiveKit Voice Agent."""

    def test_config_validation_success(self):
        with patch.object(AgentConfig, "LIVEKIT_URL", "wss://test.livekit.cloud"):
            with patch.object(AgentConfig, "LIVEKIT_API_KEY", "APITEST"):
                with patch.object(AgentConfig, "LIVEKIT_API_SECRET", "SECRETTEST"):
                    # Should not raise
                    AgentConfig.validate()

    def test_config_validation_missing_fields(self):
        with patch.object(AgentConfig, "LIVEKIT_URL", ""):
            with patch.object(AgentConfig, "LIVEKIT_API_KEY", ""):
                with patch.object(AgentConfig, "LIVEKIT_API_SECRET", ""):
                    with self.assertRaises(ValueError) as ctx:
                        AgentConfig.validate()
                    self.assertIn("Thiếu các biến cấu hình LiveKit bắt buộc", str(ctx.exception))

    def test_generate_test_tone_frames(self):
        sample_rate = 24000
        duration = 0.4
        frames = generate_test_tone_frames(
            frequency=440.0,
            duration=duration,
            sample_rate=sample_rate,
            amplitude=0.2,
        )

        # 0.4s / 0.02s per frame = 20 frames
        self.assertEqual(len(frames), 20)

        for frame in frames:
            self.assertIsInstance(frame, rtc.AudioFrame)
            self.assertEqual(frame.sample_rate, sample_rate)
            self.assertEqual(frame.num_channels, 1)
            self.assertEqual(frame.samples_per_channel, 480)  # 24000 * 0.02
            self.assertEqual(len(frame.data), 480)
            self.assertEqual(frame.data.nbytes, 960)

    def test_worker_options_construction(self):
        opts = WorkerOptions(
            entrypoint_fnc=entrypoint,
            agent_name="travelwise-voice-assistant",
            ws_url="wss://test.livekit.cloud",
            api_key="APIKEY123",
            api_secret="SECRET123456789",
        )
        self.assertEqual(opts.agent_name, "travelwise-voice-assistant")
        self.assertEqual(opts.ws_url, "wss://test.livekit.cloud")
        self.assertEqual(opts.api_key, "APIKEY123")
        self.assertIsNotNone(opts.entrypoint_fnc)


if __name__ == "__main__":
    unittest.main()
