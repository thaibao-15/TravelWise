import logging
import sys

from livekit.agents import WorkerOptions, cli

from agent import entrypoint
from config import config

# Setup structured logging
logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)

logger = logging.getLogger("travelwise.voice-agent")


def main() -> None:
    """Validate configuration and run LiveKit Agent Worker."""
    try:
        config.validate()
    except ValueError as e:
        logger.error("Lỗi cấu hình Agent: %s", e)
        sys.exit(1)

    logger.info("Khởi động TravelWise Voice Agent Worker...")
    logger.info("Tên đăng ký Agent: %s", config.LIVEKIT_AGENT_NAME)

    opts = WorkerOptions(
        entrypoint_fnc=entrypoint,
        agent_name=config.LIVEKIT_AGENT_NAME,
        ws_url=config.LIVEKIT_URL,
        api_key=config.LIVEKIT_API_KEY,
        api_secret=config.LIVEKIT_API_SECRET,
    )

    cli.run_app(opts)


if __name__ == "__main__":
    main()
