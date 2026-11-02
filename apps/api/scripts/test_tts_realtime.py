#!/usr/bin/env python3
"""Script kiểm tra Blaze TTS Realtime WebSocket V1.

Hỗ trợ 2 chế độ:
1. Chế độ câu đơn (mode=request - mặc định):
   Gửi speech.create và nhận các frame âm thanh nhị phân.
2. Chế độ luồng LLM (mode=stream):
   Gửi token qua input_text.append và kích hoạt đọc qua input_text.flush.

Cách chạy:
    uv run python scripts/test_tts_realtime.py
    uv run python scripts/test_tts_realtime.py --mode stream --text "Chào mừng bạn đến với TravelWise Đà Nẵng!"
    uv run python scripts/test_tts_realtime.py --voice HN-Nam-2-BL --speed 1.0 --model blaze-tts-2-realtime
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


async def run_request_mode(args):
    service = BlazeTTSService(
        voice=args.voice,
        speed=args.speed,
        model=args.model,
        language=args.language,
        response_format=args.format,
        sample_rate=args.sample_rate,
    )

    t_start = time.perf_counter()
    chunks = []
    ttfb = None

    print("Connecting to Blaze Realtime WebSocket (mode=request)...", end="", flush=True)

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

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(b"".join(chunks))
    print(f"[SAVE] Đã lưu file audio tại: {out_path.resolve()}")


async def run_stream_mode(args):
    service = BlazeTTSService(
        voice=args.voice,
        speed=args.speed,
        model=args.model,
        language=args.language,
        response_format=args.format,
        sample_rate=args.sample_rate,
        mode="stream",
    )

    t_start = time.perf_counter()
    chunks = []
    ttfb = None

    print("Connecting to Blaze Realtime WebSocket (mode=stream)...", end="", flush=True)
    session = await service.connect_session(overrides={"mode": "stream"})
    print("\n[OK] Session created! Active config:", session.session_config)

    tokens = args.text.split(" ")
    print(f"Simulating LLM token streaming ({len(tokens)} tokens)...")
    for token in tokens:
        await session.append_token(token + " ")
        await asyncio.sleep(0.04)

    print("Flushing buffered tokens (input_text.flush)...")
    await session.flush()

    print("Receiving audio frames: ", end="", flush=True)
    async for chunk in session.receive_speech_audio():
        now = time.perf_counter()
        if ttfb is None:
            ttfb = (now - t_start) * 1000
        chunks.append(chunk)
        print(".", end="", flush=True)

    await session.close()

    t_total = (time.perf_counter() - t_start) * 1000
    total_bytes = sum(len(c) for c in chunks)

    print(f"\n[DONE] Stream mode hoàn tất trong {t_total:.0f} ms (TTFB: {ttfb or 0:.0f} ms).")
    print(f"       Tổng số chunks : {len(chunks)}")
    print(f"       Tổng dung lượng: {total_bytes / 1024:.2f} KB ({total_bytes} bytes)")

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(b"".join(chunks))
    print(f"[SAVE] Đã lưu file audio tại: {out_path.resolve()}")


async def main():
    parser = argparse.ArgumentParser(description="Test Blaze AI TTS Realtime WebSocket V1")
    parser.add_argument(
        "--text",
        type=str,
        default="Xin chào bạn, TravelWise xin giới thiệu những bãi biển đẹp và ẩm thực nổi tiếng tại Đà Nẵng!",
        help="Nội dung văn bản cần đọc",
    )
    parser.add_argument(
        "--voice",
        "--speaker",
        dest="voice",
        type=str,
        default=settings.BLAZE_TTS_SPEAKER_ID,
        help="Mã giọng đọc (mặc định lấy từ cấu hình, ví dụ: 'HN-Nam-2-BL')",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=settings.BLAZE_TTS_MODEL,
        help="Model realtime (mặc định: 'blaze-tts-2-realtime')",
    )
    parser.add_argument(
        "--speed",
        type=str,
        default=settings.BLAZE_TTS_SPEED,
        help="Tốc độ đọc (ví dụ: '1.0', '1.2')",
    )
    parser.add_argument(
        "--format",
        type=str,
        default=settings.BLAZE_TTS_AUDIO_FORMAT,
        help="Định dạng âm thanh: mp3, opus, wav, pcm",
    )
    parser.add_argument(
        "--sample_rate",
        type=int,
        default=settings.BLAZE_TTS_SAMPLE_RATE,
        help="Tần số lấy mẫu Hz (mặc định: 24000)",
    )
    parser.add_argument(
        "--language",
        type=str,
        default=getattr(settings, "BLAZE_TTS_LANGUAGE", "vi"),
        help="Ngôn ngữ (mặc định: 'vi')",
    )
    parser.add_argument(
        "--mode",
        type=str,
        choices=["request", "stream"],
        default="request",
        help="Chế độ phiên: 'request' (từng câu) hoặc 'stream' (gom token LLM)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="data/test_realtime_audio.mp3",
        help="Đường dẫn file lưu kết quả",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("  TRAVELWISE - BLAZE TTS REALTIME TEST")
    print("=" * 60)
    print(f"WebSocket URL : {settings.BLAZE_TTS_WS_URL}")
    print(f"Model         : {args.model}")
    print(f"Voice         : {args.voice}")
    print(f"Speed         : {args.speed}")
    print(f"Format        : {args.format}")
    print(f"Sample Rate   : {args.sample_rate}")
    print(f"Language      : {args.language}")
    print(f"Mode          : {args.mode}")
    print(f"Text Input    : \"{args.text}\"")
    print("-" * 60)

    try:
        if args.mode == "stream":
            await run_stream_mode(args)
        else:
            await run_request_mode(args)
        print("-" * 60)
        print("Test hoàn tất thành công!")
    except Exception as e:
        print(f"\n[ERROR] Lỗi khi chạy TTS Realtime: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
