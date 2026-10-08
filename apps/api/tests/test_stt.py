import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app
from app.services.blaze_stt_service import BlazeSTTError, BlazeSTTService


class TestSTTRoutesAndService(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_stt_status_endpoint(self):
        response = self.client.get("/api/v1/stt/status")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("is_configured", data)
        self.assertIn("model", data)
        self.assertIn("language", data)
        self.assertIn("ws_url", data)

    def test_parse_transcript_message(self):
        # Format 1: Blaze Realtime partial transcript
        msg1 = '{"type": "partial", "text": "Hà Nội"}'
        parsed1 = BlazeSTTService.parse_transcript_message(msg1)
        self.assertIsNotNone(parsed1)
        self.assertEqual(parsed1["text"], "Hà Nội")
        self.assertFalse(parsed1["is_final"])

        # Format 2: Blaze Realtime final transcript
        msg2 = '{"type": "final", "text": "Đà Nẵng có gì vui?"}'
        parsed2 = BlazeSTTService.parse_transcript_message(msg2)
        self.assertIsNotNone(parsed2)
        self.assertEqual(parsed2["text"], "Đà Nẵng có gì vui?")
        self.assertTrue(parsed2["is_final"])

        # Format 3: error frame
        msg3 = '{"type": "error", "message": "Authentication failed"}'
        parsed3 = BlazeSTTService.parse_transcript_message(msg3)
        self.assertIsNotNone(parsed3)
        self.assertEqual(parsed3["type"], "error")

        # Invalid json
        self.assertIsNone(BlazeSTTService.parse_transcript_message("invalid json"))

    def test_service_validation_without_key(self):
        service = BlazeSTTService(api_key="")
        with self.assertRaises(BlazeSTTError):
            service.validate_configuration()

    def test_websocket_missing_key_behavior(self):
        # When BLAZE_API_KEY is missing, WebSocket should return error JSON
        with patch.object(settings, "BLAZE_API_KEY", ""):
            with self.client.websocket_connect("/api/v1/stt/ws") as websocket:
                data = websocket.receive_json()
                self.assertEqual(data.get("type"), "error")
                self.assertIn("BLAZE_API_KEY", data.get("message", ""))

    def test_websocket_connection_success(self):
        # When BLAZE_API_KEY is configured, WebSocket should connect to Blaze Realtime and acknowledge ready
        with self.client.websocket_connect("/api/v1/stt/ws") as websocket:
            data = websocket.receive_json()
            self.assertEqual(data.get("type"), "status")
            self.assertEqual(data.get("status"), "ready")
            websocket.send_json({"type": "stop"})
            stopped_data = websocket.receive_json()
            self.assertEqual(stopped_data.get("status"), "stopped")


if __name__ == "__main__":
    unittest.main()
