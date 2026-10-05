import asyncio
import json
import logging
from typing import Optional
import websockets
from websockets.exceptions import InvalidStatus

from app.core.config import settings

logger = logging.getLogger(__name__)


class BlazeSTTError(Exception):
    """Base exception for Blaze STT operations."""

    def __init__(self, message: str, status_code: int = 500):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class BlazeSTTService:
    """Service to handle realtime speech-to-text with Blaze AI (api.blaze.vn)."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        ws_url: Optional[str] = None,
        model: Optional[str] = None,
        language: Optional[str] = None,
        sample_rate: Optional[int] = None,
    ):
        self.api_key = api_key if api_key is not None else settings.BLAZE_API_KEY
        self.ws_url = ws_url or settings.BLAZE_STT_WS_URL
        self.model = model or settings.BLAZE_STT_MODEL
        self.language = language or settings.BLAZE_STT_LANGUAGE
        self.sample_rate = sample_rate or settings.BLAZE_STT_SAMPLE_RATE

    def validate_configuration(self) -> None:
        """Ensure necessary configuration exists."""
        if not self.api_key or not self.api_key.strip():
            raise BlazeSTTError(
                "BLAZE_API_KEY chưa được cấu hình trong .env. Vui lòng thêm BLAZE_API_KEY để sử dụng tính năng STT.",
                status_code=401,
            )

    async def connect(self):
        """Establish native WebSocket connection to Blaze AI STT Realtime."""
        self.validate_configuration()

        url = self.ws_url or "wss://api.blaze.vn/v1/stt/realtime"
        logger.info("Connecting to Blaze AI STT Realtime at %s (model=%s, lang=%s)", url, self.model, self.language)

        try:
            ws = await websockets.connect(
                url,
                ping_interval=20,
                ping_timeout=20,
            )

            # Send authentication payload as first frame
            auth_payload = {
                "token": self.api_key.strip(),
                "language": self.language,
                "model": self.model,
            }
            await ws.send(json.dumps(auth_payload))

            # Wait for ready signal from Blaze AI
            while True:
                msg_raw = await ws.recv()
                if isinstance(msg_raw, str):
                    data = json.loads(msg_raw)
                    msg_type = data.get("type")
                    if msg_type == "ready":
                        logger.info("Blaze AI STT Realtime is ready to receive audio")
                        break
                    elif msg_type == "error":
                        err_text = data.get("message") or "Lỗi xác thực từ máy chủ Blaze AI"
                        raise BlazeSTTError(err_text, status_code=401)
                    elif msg_type == "successful-authentication":
                        logger.debug("Blaze AI authentication successful, waiting for ready frame")

            return ws

        except InvalidStatus as e:
            status_code = getattr(e.response, "status_code", 500)
            if status_code in (401, 403):
                raise BlazeSTTError("Blaze API Key không hợp lệ hoặc không có quyền truy cập.", status_code=401)
            raise BlazeSTTError(f"Không thể kết nối đến Blaze STT Realtime (HTTP {status_code})", status_code=502)
        except BlazeSTTError:
            raise
        except Exception as e:
            logger.error("Failed to connect to Blaze STT Realtime: %s", e)
            raise BlazeSTTError(f"Lỗi kết nối tới máy chủ Blaze AI STT Realtime: {str(e)}", status_code=503)

    @staticmethod
    def parse_transcript_message(raw_msg: str) -> Optional[dict]:
        """Extract transcript text and finality flag from Blaze JSON response."""
        try:
            data = json.loads(raw_msg)
        except Exception:
            return None

        if isinstance(data, dict):
            msg_type = data.get("type")
            if msg_type == "error" or "error" in data:
                error_msg = data.get("message") or data.get("error") or "Lỗi từ dịch vụ Blaze STT"
                return {"type": "error", "message": str(error_msg)}

            # Blaze Realtime uses: type == "partial" or type == "final"
            text = (
                data.get("text")
                or data.get("transcript")
                or data.get("transcription")
                or ""
            )

            is_final = bool(
                msg_type == "final"
                or data.get("is_final")
                or data.get("final")
            )

            if text and text.strip():
                return {
                    "type": "transcript",
                    "text": text.strip(),
                    "is_final": is_final,
                }

        return None
