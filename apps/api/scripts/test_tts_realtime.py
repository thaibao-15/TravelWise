#!/usr/bin/env python3
"""Script kiểm tra Blaze TTS Realtime WebSocket.

Cách chạy:
    uv run python scripts/test_tts_realtime.py
    uv run python scripts/test_tts_realtime.py --text "Cầu Rồng Đà Nẵng phun lửa vào cuối tuần." --speed 1.5
"""

import argparse
import asyncio
import os
import sys
import time
from pathlib import Path

# Thiết lập UTF-8 encoding cho Windows stdout
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

# Thêm thư mục gốc apps/api vào sys.path để import app.*
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import settings
from app.services.tts_service import BlazeTTSService


async def main():
    parser = argparse.ArgumentParser(description="Test Blaze AI TTS Realtime WebSocket")
    parser.add_argument(
        "--text",
        type=str,
        default="Xin chào bạn, TravelWise xin giới thiệu những bãi biển đẹp và ẩm thực nổi tiếng tại Đà Nẵng!",
        help="Nội dung văn bản cần đọc",
    )
    parser.add_argument(
        "--speaker",
        type=str,
        default=settings.BLAZE_TTS_SPEAKER_ID,
        help="Mã giọng đọc (mặc định lấy từ cấu hình)",
    )
    parser.add_argument(
        "--speed",
        type=str,
        default=settings.BLAZE_TTS_SPEED,
        help="Tốc độ đọc (ví dụ: '1', '1.2', '1.5')",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="data/test_realtime_audio.mp3",
        help="Đường dẫn file MP3 lưu kết quả",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("  TRAVELWISE - BLAZE TTS REALTIME TEST")
    print("=" * 60)
    print(f"WebSocket URL : {settings.BLAZE_TTS_WS_URL}")
    print(f"Model         : {settings.BLAZE_TTS_MODEL}")
    print(f"Speaker ID    : {args.speaker}")
    print(f"Speed         : {args.speed}")
    print(f"Format        : {settings.BLAZE_TTS_AUDIO_FORMAT}")
    print(f"Text Input    : \"{args.text}\"")
    print("-" * 60)

    service = BlazeTTSService(
        speaker_id=args.speaker,
        speed=args.speed,
    )

    t_start = time.perf_counter()
    chunks = []
    ttfb = None

    print("Connecting to Blaze Realtime WebSocket...", end="", flush=True)

    try:
        async for chunk in service.stream_speech(args.text):
            now = time.perf_counter()
            if ttfb is None:
                ttfb = (now - t_start) * 1000
                print(f"\n[OK] First chunk received (TTFB: {ttfb:.0f} ms)! Streaming audio: ", end="", flush=True)

            chunks.append(chunk)
            print(".", end="", flush=True)

        t_total = (time.perf_counter() - t_start) * 1000
        total_bytes = sum(len(c) for c in chunks)

        print(f"\n[DONE] Hoàn thành luồng stream trong {t_total:.0f} ms.")
        print(f"       Tổng số chunks : {len(chunks)}")
        print(f"       Tổng dung lượng: {total_bytes / 1024:.2f} KB ({total_bytes} bytes)")

        # Lưu file mp3
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(b"".join(chunks))
        print(f"[SAVE] Đã lưu file audio tại: {out_path.resolve()}")
        print("-" * 60)
        print("Test hoàn tất thành công!")

    except Exception as e:
        print(f"\n[ERROR] Lỗi khi tạo TTS Realtime: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
