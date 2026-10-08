import unittest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient

from app.main import app
from app.services.tts_service import BlazeTTSError, BlazeTTSService


class TestTTSRoutesAndService(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_tts_status_endpoint(self):
        response = self.client.get("/api/v1/tts/status")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("is_configured", data)
        self.assertIn("speaker_id", data)
        self.assertIn("model", data)
        self.assertIn("audio_format", data)

    def test_tts_empty_text_validation(self):
        response = self.client.post("/api/v1/tts", json={"text": ""})
        self.assertIn(response.status_code, (400, 422))

    def test_service_validation_without_key(self):
        service = BlazeTTSService(api_key="")
        with self.assertRaises(BlazeTTSError):
            service.validate_configuration()

    @patch.object(BlazeTTSService, "synthesize_speech", new_callable=AsyncMock)
    def test_tts_endpoint_success(self, mock_synthesize):
        mock_synthesize.return_value = b"RIFF....WAVEfmt...."
        response = self.client.post(
            "/api/v1/tts",
            json={"text": "Chào mừng bạn đến với TravelWise."},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "audio/wav")
        self.assertEqual(response.content, b"RIFF....WAVEfmt....")


if __name__ == "__main__":
    unittest.main()
