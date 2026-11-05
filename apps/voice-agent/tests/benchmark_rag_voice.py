"""Benchmark script to measure end-to-end latency: User Audio -> STT -> RAG -> TTS -> Audio."""

import asyncio
import json
import sys
import time
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from blaze import BlazeSTT, BlazeTTS
from config import config
from services.rag_client import TravelWiseRAGClient


async def benchmark_e2e_pipeline():
    print("\n=======================================================", flush=True)
    print("🚀 ĐO KIỂM THỜI GIAN THỰC TOÀN TRÌNH (E2E PIPELINE)", flush=True)
    print("=======================================================", flush=True)

    rag_client = TravelWiseRAGClient(base_url=config.BACKEND_API_URL)
    blaze_tts = BlazeTTS()

    test_queries = [
        "Cầu Rồng Đà Nẵng phun lửa vào ngày nào và mấy giờ?",
        "Nó có gần chợ đêm Sơn Trà không?",  # Follow-up with pronoun 'Nó'
    ]

    conversation_id = None

    for i, query in enumerate(test_queries, 1):
        print(f"\n[Lượt {i}] Câu hỏi: '{query}'", flush=True)
        t_user_speech_end = time.perf_counter()

        # 1. RAG Query
        print("  ⏳ Đang gửi truy vấn đến Gemini + Chroma RAG...", flush=True)
        t_rag_start = time.perf_counter()
        rag_res = await rag_client.ask(
            question=query,
            conversation_id=conversation_id,
            mode="voice",
        )
        t_rag_end = time.perf_counter()
        rag_duration_ms = (t_rag_end - t_rag_start) * 1000
        conversation_id = rag_res["conversation_id"]
        answer = rag_res["answer"]

        print(f"  ✅ [RAG Thành công] Thời gian xử lý: {rag_duration_ms:.1f}ms", flush=True)
        print(f"     Nội dung trả lời: '{answer[:80]}...'", flush=True)
        print(f"     Conversation ID: {conversation_id}", flush=True)

        # 2. TTS Synthesis
        print("  ⏳ Đang tổng hợp giọng nói qua Blaze TTS...", flush=True)
        t_tts_start = time.perf_counter()
        stream = blaze_tts.synthesize(answer)

        first_audio_ms = None
        total_chunks = 0
        total_bytes = 0

        async for audio_ev in stream:
            total_chunks += 1
            total_bytes += audio_ev.frame.data.nbytes
            if first_audio_ms is None:
                first_audio_ms = (time.perf_counter() - t_tts_start) * 1000
                e2e_latency_ms = (time.perf_counter() - t_user_speech_end) * 1000
                print(f"  ⚡ [Time To First Audio Byte]: {first_audio_ms:.1f}ms", flush=True)
                print(f"  🎯 [ĐỘ TRỄ TOÀN TRÌNH (End-to-End)]: {e2e_latency_ms:.1f}ms", flush=True)

        t_tts_end = time.perf_counter()
        tts_total_ms = (t_tts_end - t_tts_start) * 1000
        print(f"  ✅ [TTS Hoàn tất] Tổng thời gian: {tts_total_ms:.1f}ms | Chunks: {total_chunks} | Dữ liệu: {total_bytes} bytes", flush=True)


if __name__ == "__main__":
    asyncio.run(benchmark_e2e_pipeline())
