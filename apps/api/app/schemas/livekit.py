from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class LiveKitTokenRequest(BaseModel):
    """Payload to request a LiveKit Room Access Token."""

    conversation_id: Optional[int] = Field(
        default=None,
        description="ID cuộc trò chuyện hiện có. Nếu không cung cấp, hệ thống sẽ tự động tạo cuộc trò chuyện mới.",
        examples=[15],
    )
    room_name: Optional[str] = Field(
        default=None,
        description="Tên phòng LiveKit tùy chỉnh. Nếu để trống, hệ thống sẽ tự sinh tên theo chuẩn travelwise_conv_{id}.",
        examples=["travelwise_conv_15"],
    )

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "conversation_id": 15,
            }
        }
    )


class LiveKitTokenResponse(BaseModel):
    """Response containing LiveKit connection details and generated Access Token."""

    server_url: str = Field(
        ...,
        description="WebSocket URL của LiveKit Server hoặc LiveKit Cloud",
        examples=["wss://travewise-yi9ty5dg.livekit.cloud"],
    )
    token: str = Field(
        ...,
        description="JWT Access Token đã ký để trình duyệt kết nối trực tiếp vào phòng WebRTC",
    )
    room_name: str = Field(
        ...,
        description="Tên phòng WebRTC LiveKit được cấp quyền tham gia",
        examples=["travelwise_conv_15"],
    )
    identity: str = Field(
        ...,
        description="Định danh duy nhất của người tham gia trong phòng (ví dụ: user_1)",
        examples=["user_1"],
    )
    conversation_id: int = Field(
        ...,
        description="ID cuộc trò chuyện TravelWise liên kết với phiên thoại này",
        examples=[15],
    )


class LiveKitStatusResponse(BaseModel):
    """Status of LiveKit configuration on the server."""

    is_configured: bool
    server_url: Optional[str] = None
    agent_name: str
