import datetime
import json
import logging
from typing import Any, Dict, Optional

from livekit.api import AccessToken, VideoGrants
from livekit.protocol.agent_dispatch import RoomAgentDispatch
from livekit.protocol.room import RoomConfiguration

from app.core.config import settings

logger = logging.getLogger(__name__)


class LiveKitError(Exception):
    """Base exception for LiveKit operations."""

    def __init__(self, message: str, status_code: int = 500):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class LiveKitService:
    """Service handling LiveKit server credentials, room management and token generation."""

    def __init__(
        self,
        server_url: Optional[str] = None,
        api_key: Optional[str] = None,
        api_secret: Optional[str] = None,
        agent_name: Optional[str] = None,
        ttl_minutes: Optional[int] = None,
    ):
        self.server_url = server_url if server_url is not None else settings.LIVEKIT_URL
        self.api_key = api_key if api_key is not None else settings.LIVEKIT_API_KEY
        self.api_secret = api_secret if api_secret is not None else settings.LIVEKIT_API_SECRET
        self.agent_name = agent_name if agent_name is not None else settings.LIVEKIT_AGENT_NAME
        self.ttl_minutes = ttl_minutes if ttl_minutes is not None else getattr(settings, "LIVEKIT_TOKEN_TTL_MINUTES", 60)

    def is_configured(self) -> bool:
        """Check whether all required LiveKit credentials are configured."""
        return bool(
            self.server_url
            and self.server_url.strip()
            and self.api_key
            and self.api_key.strip()
            and self.api_secret
            and self.api_secret.strip()
        )

    def validate_configuration(self) -> None:
        """Validate configuration and raise LiveKitError if missing."""
        if not self.is_configured():
            logger.warning("LiveKit credentials not configured in environment.")
            raise LiveKitError(
                "Chưa cấu hình đầy đủ LiveKit (LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET) trong hệ thống.",
                status_code=503,
            )

    def create_token(
        self,
        user_id: int,
        user_name: Optional[str],
        room_name: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> str:
        """Generate a cryptographically signed LiveKit Access Token for a user.

        Args:
            user_id: Unique integer ID of the TravelWise user.
            user_name: Display name or email of the user.
            room_name: Target WebRTC room to join.
            metadata: Custom contextual data dictionary to attach to the participant.

        Returns:
            JWT token string ready for frontend LiveKit client SDK connection.
        """
        self.validate_configuration()

        clean_room = (room_name or "").strip()
        if not clean_room:
            raise LiveKitError("Tên phòng LiveKit (room_name) không được để trống.", status_code=400)

        identity = f"user_{user_id}"
        display_name = (user_name or "").strip() or f"User {user_id}"

        # 1. Define participant permissions (grants)
        grants = VideoGrants(
            room_join=True,
            room=clean_room,
            can_publish=True,
            can_subscribe=True,
            can_publish_data=True,
        )

        # 2. Build token with TTL and grants
        ttl = datetime.timedelta(minutes=self.ttl_minutes)
        token_builder = (
            AccessToken(api_key=self.api_key.strip(), api_secret=self.api_secret.strip())
            .with_identity(identity)
            .with_name(display_name)
            .with_grants(grants)
            .with_ttl(ttl)
        )

        # 3. Attach metadata if provided
        if metadata is not None:
            token_builder = token_builder.with_metadata(json.dumps(metadata, ensure_ascii=False))

        # 4. Attach agent dispatch configuration if agent_name is configured
        if self.agent_name and self.agent_name.strip():
            agent_dispatch = RoomAgentDispatch(agent_name=self.agent_name.strip())
            room_config = RoomConfiguration(
                name=clean_room,
                agents=[agent_dispatch],
            )
            token_builder = token_builder.with_room_config(room_config)

        try:
            jwt_token = token_builder.to_jwt()
            return jwt_token
        except Exception as e:
            logger.error("Failed to generate LiveKit token: %s", type(e).__name__)
            raise LiveKitError("Lỗi hệ thống khi khởi tạo token LiveKit.", status_code=500) from None
