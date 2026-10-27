import os
from pathlib import Path
from dotenv import load_dotenv

# Search for .env in current directory, then parent apps/api/.env
current_dir = Path(__file__).resolve().parent
local_env = current_dir / ".env"
parent_api_env = current_dir.parent / "api" / ".env"

if local_env.exists():
    load_dotenv(local_env)
elif parent_api_env.exists():
    load_dotenv(parent_api_env)
else:
    load_dotenv()


class AgentConfig:
    LIVEKIT_URL: str = os.getenv("LIVEKIT_URL", "").strip()
    LIVEKIT_API_KEY: str = os.getenv("LIVEKIT_API_KEY", "").strip()
    LIVEKIT_API_SECRET: str = os.getenv("LIVEKIT_API_SECRET", "").strip()
    LIVEKIT_AGENT_NAME: str = os.getenv("LIVEKIT_AGENT_NAME", "travelwise-voice-assistant").strip()
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").strip().upper()

    # Blaze AI STT & TTS Configuration
    BLAZE_API_KEY: str = os.getenv("BLAZE_API_KEY", "").strip()
    BLAZE_STT_WS_URL: str = os.getenv("BLAZE_STT_WS_URL", "wss://api.blaze.vn/v1/stt/realtime").strip()
    BLAZE_STT_MODEL: str = os.getenv("BLAZE_STT_MODEL", "stt-stream-1.5").strip()
    BLAZE_STT_LANGUAGE: str = os.getenv("BLAZE_STT_LANGUAGE", "vi").strip()
    BLAZE_STT_SAMPLE_RATE: int = int(os.getenv("BLAZE_STT_SAMPLE_RATE", "16000"))

    BLAZE_TTS_WS_URL: str = os.getenv("BLAZE_TTS_WS_URL", "wss://api.blaze.vn/v1/tts/realtime").strip()
    BLAZE_TTS_SPEAKER_ID: str = os.getenv("BLAZE_TTS_SPEAKER_ID", "DaNang-Nu-1-BL").strip()
    BLAZE_TTS_MODEL: str = os.getenv("BLAZE_TTS_MODEL", "2.0-realtime").strip()
    BLAZE_TTS_SPEED: str = os.getenv("BLAZE_TTS_SPEED", "1.5").strip()
    BLAZE_TTS_AUDIO_QUALITY: int = int(os.getenv("BLAZE_TTS_AUDIO_QUALITY", "64"))
    BLAZE_TTS_AUDIO_FORMAT: str = os.getenv("BLAZE_TTS_AUDIO_FORMAT", "mp3").strip()
    BLAZE_TTS_NORMALIZATION: str = os.getenv("BLAZE_TTS_NORMALIZATION", "basic").strip()

    # Backend FastAPI API & Security Configuration
    BACKEND_API_URL: str = os.getenv("BACKEND_API_URL", "http://127.0.0.1:8000").strip()
    JWT_SECRET: str = os.getenv("JWT_SECRET", "your-secret-key").strip()
    JWT_ALGORITHM: str = os.getenv("JWT_ALGORITHM", "HS256").strip()

    @classmethod
    def validate(cls) -> None:
        """Ensure necessary credentials exist without revealing them."""
        missing = []
        if not cls.LIVEKIT_URL:
            missing.append("LIVEKIT_URL")
        if not cls.LIVEKIT_API_KEY:
            missing.append("LIVEKIT_API_KEY")
        if not cls.LIVEKIT_API_SECRET:
            missing.append("LIVEKIT_API_SECRET")

        if missing:
            raise ValueError(
                f"Thiếu các biến cấu hình LiveKit bắt buộc: {', '.join(missing)}. "
                "Vui lòng cấu hình trong file .env."
            )

    @classmethod
    def validate_blaze(cls) -> None:
        """Validate that Blaze AI API key is configured."""
        if not cls.BLAZE_API_KEY:
            raise ValueError(
                "BLAZE_API_KEY chưa được cấu hình. "
                "Vui lòng cấu hình BLAZE_API_KEY trong file .env để sử dụng Blaze AI STT/TTS."
            )


config = AgentConfig()

