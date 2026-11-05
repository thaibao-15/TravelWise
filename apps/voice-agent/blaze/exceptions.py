"""Custom exceptions for Blaze AI STT and TTS LiveKit adapters."""

from livekit.agents import APIConnectionError, APIError, APIStatusError, APITimeoutError


class BlazeError(APIError):
    """Base exception for all Blaze AI adapter operations."""

    def __init__(self, message: str = "Blaze AI error", *, retryable: bool = True) -> None:
        super().__init__(message, retryable=retryable)


class BlazeAuthError(APIStatusError):
    """Authentication or authorization failure with Blaze AI."""

    def __init__(self, message: str = "Xác thực Blaze AI thất bại (API Key không hợp lệ).") -> None:
        super().__init__(message, status_code=401, retryable=False)


class BlazeSTTError(BlazeError):
    """Base exception for Blaze AI Speech-To-Text operations."""

    pass


class BlazeTTSError(BlazeError):
    """Base exception for Blaze AI Text-To-Speech operations."""

    pass


class BlazeConnectionError(APIConnectionError):
    """Connection error when communicating with Blaze AI WebSockets."""

    def __init__(self, message: str = "Không thể kết nối đến máy chủ Blaze AI.") -> None:
        super().__init__(message, retryable=True)


class BlazeTimeoutError(APITimeoutError):
    """Timeout error when waiting for Blaze AI responses."""

    def __init__(self, message: str = "Quá thời gian chờ phản hồi từ máy chủ Blaze AI.") -> None:
        super().__init__(message, retryable=True)
