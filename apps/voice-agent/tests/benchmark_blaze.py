"""Benchmark script to measure real-world Blaze STT and TTS latency."""

import asyncio
import json
import sys
import time
from pathlib import Path
import websockets

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from config import config


async def benchmark_stt():
    print("\n--- Đo kiểm thực tế Blaze STT WebSocket ---", flush=True)
    print(f"  BLAZE_API_KEY loaded: {bool(config.BLAZE_API_KEY)} (len: {len(config.BLAZE_API_KEY)})", flush=True)
    print(f"  BLAZE_STT_WS_URL: {config.BLAZE_STT_WS_URL}", flush=True)

    start = time.perf_counter()
    async with websockets.connect(config.BLAZE_STT_WS_URL, max_size=10 * 1024 * 1024, open_timeout=5) as ws:
        connected_time = time.perf_counter()
        connect_latency = (connected_time - start) * 1000
        print(f"  WebSocket Connect Latency: {connect_latency:.1f}ms", flush=True)

        payload = {
            "token": config.BLAZE_API_KEY,
            "language": config.BLAZE_STT_LANGUAGE,
            "model": config.BLAZE_STT_MODEL,
        }
        await ws.send(json.dumps(payload))
        ready_start = time.perf_counter()

        while True:
            msg = await asyncio.wait_for(ws.recv(), timeout=5)
            if isinstance(msg, str):
                data = json.loads(msg)
                msg_type = data.get("type")
                print(f"  Received message from STT: {msg_type} -> {data}", flush=True)
                if msg_type == "ready":
                    break

        ready_latency = (time.perf_counter() - ready_start) * 1000
        total_handshake = (time.perf_counter() - start) * 1000

        print(f"  Auth-to-Ready Latency:    {ready_latency:.1f}ms", flush=True)
        print(f"  Total STT Ready Latency:  {total_handshake:.1f}ms", flush=True)


async def benchmark_tts():
    print("\n--- Đo kiểm thực tế Blaze TTS WebSocket ---", flush=True)
    text = "Xin chào, tôi là trợ lý ảo TravelWise AI. Tôi có thể giúp gì cho chuyến du lịch Đà Nẵng của bạn?"
    start = time.perf_counter()

    async with websockets.connect(config.BLAZE_TTS_WS_URL, max_size=10 * 1024 * 1024, open_timeout=5) as ws:
        connected_time = time.perf_counter()
        connect_latency = (connected_time - start) * 1000
        print(f"  WebSocket Connect Latency: {connect_latency:.1f}ms", flush=True)

        auth_payload = {
            "token": config.BLAZE_API_KEY,
            "strategy": "request",
        }
        await ws.send(json.dumps(auth_payload))

        query_payload = {
            "query": text,
            "language": "vi",
            "audio_format": config.BLAZE_TTS_AUDIO_FORMAT,
            "audio_quality": config.BLAZE_TTS_AUDIO_QUALITY,
            "audio_speed": str(config.BLAZE_TTS_SPEED),
            "speaker_id": config.BLAZE_TTS_SPEAKER_ID,
            "normalization": config.BLAZE_TTS_NORMALIZATION,
            "model": config.BLAZE_TTS_MODEL,
        }
        send_time = time.perf_counter()
        await ws.send(json.dumps(query_payload))


        ttfb = None
        first_chunk_time = None
        total_chunks = 0
        total_bytes = 0

        while True:
            msg = await asyncio.wait_for(ws.recv(), timeout=10)
            if isinstance(msg, bytes):
                total_chunks += 1
                total_bytes += len(msg)
                if ttfb is None:
                    first_chunk_time = time.perf_counter()
                    ttfb = (first_chunk_time - send_time) * 1000
            elif isinstance(msg, str):
                data = json.loads(msg)
                if data.get("type") == "finished-byte-stream":
                    break

        end_time = time.perf_counter()
        total_time = (end_time - send_time) * 1000

        print(f"  Time To First Byte (TTFB): {ttfb:.1f}ms", flush=True)
        print(f"  Total Synthesis Duration:  {total_time:.1f}ms", flush=True)
        print(f"  Received Audio Chunks:     {total_chunks}", flush=True)
        print(f"  Received Total Audio Data: {total_bytes} bytes ({total_bytes / 1024:.1f} KB)", flush=True)


async def main():
    try:
        await benchmark_stt()
    except Exception as e:
        print(f"  Blaze STT benchmark error: {e}", flush=True)

    try:
        await benchmark_tts()
    except Exception as e:
        import traceback
        print(f"  Blaze TTS benchmark error: {type(e).__name__}: {e}\n{traceback.format_exc()}", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
