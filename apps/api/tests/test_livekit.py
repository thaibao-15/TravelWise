import unittest
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient

from app.api.deps import get_current_user, get_session
from app.core.config import settings
from app.main import app
from app.models.conversation import Conversation
from app.models.user import User
from app.services.livekit_service import LiveKitError, LiveKitService


class TestLiveKitServiceUnit(unittest.TestCase):
    """Unit tests for LiveKitService configuration and token creation."""

    def test_is_configured_true(self):
        service = LiveKitService(
            server_url="wss://test.livekit.cloud",
            api_key="API12345678",
            api_secret="SECRET12345678901234567890123456",
        )
        self.assertTrue(service.is_configured())

    def test_is_configured_false_when_missing_fields(self):
        service = LiveKitService(server_url="", api_key="key", api_secret="secret")
        self.assertFalse(service.is_configured())

        service2 = LiveKitService(server_url="wss://test.cloud", api_key="", api_secret="secret")
        self.assertFalse(service2.is_configured())

        service3 = LiveKitService(server_url="wss://test.cloud", api_key="key", api_secret="")
        self.assertFalse(service3.is_configured())

    def test_validate_configuration_raises_503(self):
        service = LiveKitService(server_url="", api_key="", api_secret="")
        with self.assertRaises(LiveKitError) as ctx:
            service.validate_configuration()
        self.assertEqual(ctx.exception.status_code, 503)

    def test_create_token_success(self):
        service = LiveKitService(
            server_url="wss://test.livekit.cloud",
            api_key="devkey",
            api_secret="secret12345678901234567890123456",
            agent_name="travelwise-voice-assistant",
        )
        token = service.create_token(
            user_id=42,
            user_name="Nguyen Van A",
            room_name="travelwise_conv_99",
            metadata={"conversation_id": 99, "user_id": 42},
        )
        self.assertIsInstance(token, str)
        self.assertTrue(len(token) > 50)

    def test_create_token_empty_room_raises_400(self):
        service = LiveKitService(
            server_url="wss://test.livekit.cloud",
            api_key="devkey",
            api_secret="secret12345678901234567890123456",
        )
        with self.assertRaises(LiveKitError) as ctx:
            service.create_token(user_id=1, user_name="User", room_name="   ")
        self.assertEqual(ctx.exception.status_code, 400)


class TestLiveKitEndpoints(unittest.TestCase):
    """Integration and authorization tests for LiveKit REST endpoints."""

    def setUp(self):
        self.client = TestClient(app)
        self.mock_user = User(
            id=10,
            email="testuser@example.com",
            full_name="Test User",
            role="USER",
            is_active=True,
        )
        self.mock_other_user = User(
            id=20,
            email="otheruser@example.com",
            full_name="Other User",
            role="USER",
            is_active=True,
        )

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_livekit_status_endpoint(self):
        """GET /api/v1/livekit/status returns configuration status."""
        response = self.client.get("/api/v1/livekit/status")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("is_configured", data)
        self.assertIn("agent_name", data)
        self.assertEqual(data["agent_name"], settings.LIVEKIT_AGENT_NAME)

    def test_token_unauthenticated_returns_401(self):
        """POST /api/v1/livekit/token without credentials returns 401."""
        response = self.client.post("/api/v1/livekit/token", json={})
        self.assertEqual(response.status_code, 401)

    def test_token_missing_configuration_returns_503(self):
        """POST /api/v1/livekit/token returns 503 when LiveKit is not configured."""
        app.dependency_overrides[get_current_user] = lambda: self.mock_user

        with patch.object(settings, "LIVEKIT_API_KEY", ""):
            response = self.client.post("/api/v1/livekit/token", json={})
            self.assertEqual(response.status_code, 503)
            self.assertIn("Chưa cấu hình đầy đủ LiveKit", response.json()["detail"])

    def test_token_authenticated_creates_conversation_and_token(self):
        """POST /api/v1/livekit/token with authenticated user and no conversation_id creates new room."""
        app.dependency_overrides[get_current_user] = lambda: self.mock_user

        mock_session = MagicMock()
        mock_conv = Conversation(id=101, user_id=self.mock_user.id, title="Cuộc trò chuyện thoại LiveKit")

        with patch("app.services.conversation_service.ConversationService.create_conversation", return_value=mock_conv):
            with patch.object(settings, "LIVEKIT_URL", "wss://travewise-yi9ty5dg.livekit.cloud"):
                with patch.object(settings, "LIVEKIT_API_KEY", "APICK5jXw5vaWLb"):
                    with patch.object(settings, "LIVEKIT_API_SECRET", "QQG7hsv0uznE8IMafwOSATAJC2HXzf2POJ7eix5qEUOA"):
                        app.dependency_overrides[get_session] = lambda: mock_session

                        response = self.client.post("/api/v1/livekit/token", json={})
                        self.assertEqual(response.status_code, 200)
                        data = response.json()

                        self.assertEqual(data["server_url"], "wss://travewise-yi9ty5dg.livekit.cloud")
                        self.assertIn("token", data)
                        self.assertTrue(len(data["token"]) > 30)
                        self.assertEqual(data["room_name"], "travelwise_conv_101")
                        self.assertEqual(data["identity"], f"user_{self.mock_user.id}")
                        self.assertEqual(data["conversation_id"], 101)

    def test_token_authenticated_existing_conversation_success(self):
        """POST /api/v1/livekit/token with owned conversation_id returns 200."""
        app.dependency_overrides[get_current_user] = lambda: self.mock_user

        mock_session = MagicMock()
        mock_conv = Conversation(id=77, user_id=self.mock_user.id, title="Chuyến đi Đà Nẵng")

        with patch("app.services.conversation_service.ConversationService.get_conversation_by_id", return_value=mock_conv):
            with patch.object(settings, "LIVEKIT_URL", "wss://travewise-yi9ty5dg.livekit.cloud"):
                with patch.object(settings, "LIVEKIT_API_KEY", "APICK5jXw5vaWLb"):
                    with patch.object(settings, "LIVEKIT_API_SECRET", "QQG7hsv0uznE8IMafwOSATAJC2HXzf2POJ7eix5qEUOA"):
                        app.dependency_overrides[get_session] = lambda: mock_session

                        response = self.client.post("/api/v1/livekit/token", json={"conversation_id": 77})
                        self.assertEqual(response.status_code, 200)
                        data = response.json()

                        self.assertEqual(data["conversation_id"], 77)
                        self.assertEqual(data["room_name"], "travelwise_conv_77")
                        self.assertEqual(data["identity"], f"user_{self.mock_user.id}")

    def test_token_forbidden_for_other_user_conversation(self):
        """POST /api/v1/livekit/token returns 403 when accessing someone else's conversation."""
        from fastapi import HTTPException, status

        app.dependency_overrides[get_current_user] = lambda: self.mock_user
        mock_session = MagicMock()

        def raise_forbidden(*args, **kwargs):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền truy cập cuộc trò chuyện này.",
            )

        with patch("app.services.conversation_service.ConversationService.get_conversation_by_id", side_effect=raise_forbidden):
            with patch.object(settings, "LIVEKIT_URL", "wss://travewise-yi9ty5dg.livekit.cloud"):
                with patch.object(settings, "LIVEKIT_API_KEY", "APICK5jXw5vaWLb"):
                    with patch.object(settings, "LIVEKIT_API_SECRET", "QQG7hsv0uznE8IMafwOSATAJC2HXzf2POJ7eix5qEUOA"):
                        app.dependency_overrides[get_session] = lambda: mock_session

                        response = self.client.post("/api/v1/livekit/token", json={"conversation_id": 999})
                        self.assertEqual(response.status_code, 403)
                        self.assertIn("Bạn không có quyền", response.json()["detail"])

    def test_token_not_found_conversation(self):
        """POST /api/v1/livekit/token returns 404 when conversation does not exist."""
        from fastapi import HTTPException, status

        app.dependency_overrides[get_current_user] = lambda: self.mock_user
        mock_session = MagicMock()

        def raise_not_found(*args, **kwargs):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy cuộc trò chuyện với ID 9999",
            )

        with patch("app.services.conversation_service.ConversationService.get_conversation_by_id", side_effect=raise_not_found):
            with patch.object(settings, "LIVEKIT_URL", "wss://travewise-yi9ty5dg.livekit.cloud"):
                with patch.object(settings, "LIVEKIT_API_KEY", "APICK5jXw5vaWLb"):
                    with patch.object(settings, "LIVEKIT_API_SECRET", "QQG7hsv0uznE8IMafwOSATAJC2HXzf2POJ7eix5qEUOA"):
                        app.dependency_overrides[get_session] = lambda: mock_session

                        response = self.client.post("/api/v1/livekit/token", json={"conversation_id": 9999})
                        self.assertEqual(response.status_code, 404)
