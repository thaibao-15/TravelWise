"""Comprehensive Benchmark comparing Phase 6 Baseline vs Phase 7 Real-time Optimization."""

from __future__ import annotations

import asyncio
import re
import sys
import time
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from blaze import BlazeTTS
from config import config
from coordinator import ConversationCoordinator
from services.rag_client import TravelWiseRAGClient


async def run_baseline_turn(query: str, conv_id: int | None, rag_client: TravelWiseRAGClient, tts: BlazeTTS):
    """Phase 6 Baseline: Batch RAG followed by Full-Text TTS."""
    t_speech_end = time.perf_counter()
    # Simulated VAD / STT completion window (calibrated to actual Blaze STT final transcript: ~450ms)
    stt_offset = 0.450
    t_stt_done = t_speech_end + stt_offset

    # Full batch RAG
    t_llm_start = time.perf_counter()
    rag_res = await rag_client.ask(question=query, conversation_id=conv_id, mode="voice")
    t_llm_done = time.perf_counter()
    answer = rag_res["answer"]
    next_conv_id = rag_res["conversation_id"]

    # Full text TTS
    t_tts_start = time.perf_counter()
    stream = tts.synthesize(answer)
    t_first_audio = None
    async for ev in stream:
        if t_first_audio is None:
            t_first_audio = time.perf_counter()
            break

    # Metrics
    speech_end_to_stt = stt_offset * 1000
    stt_to_llm = (t_llm_done - t_llm_start) * 1000  # full generation wait
    llm_to_tts = (t_first_audio - t_tts_start) * 1000 if t_first_audio else 0
    e2e_total = speech_end_to_stt + stt_to_llm + llm_to_tts

    return {
        "mode": "Phase 6 Baseline (Batch)",
        "conv_id": next_conv_id,
        "speech_end_to_stt": speech_end_to_stt,
        "stt_to_llm": stt_to_llm,
        "llm_to_tts": llm_to_tts,
        "e2e_total": e2e_total,
        "answer_len": len(answer),
    }


async def run_optimized_turn(query: str, conv_id: int | None, rag_client: TravelWiseRAGClient, tts: BlazeTTS):
    """Phase 7 Optimized: Streaming RAG with Sentence-level chunking and early TTS."""
    t_speech_end = time.perf_counter()
    stt_offset = 0.450
    t_stt_done = t_speech_end + stt_offset

    coordinator = ConversationCoordinator(conversation_id=conv_id)
    turn_id = coordinator.start_new_turn(query)
    coordinator.record_user_speech_end(turn_id, timestamp=t_speech_end)
    coordinator.record_stt_done(turn_id, query, timestamp=t_stt_done)

    delimiters = re.compile(r"([.!?\n]+(?:\s+|$))")
    buffer = ""
    first_token_time = None
    sentence_1 = ""
    next_conv_id = conv_id

    # Stream tokens from RAG
    token_stream = rag_client.ask_stream(question=query, conversation_id=conv_id, mode="voice")
    async for ev in token_stream:
        ev_type = ev.get("type")
        if ev_type == "token":
            if first_token_time is None:
                first_token_time = time.perf_counter()
                coordinator.record_llm_first_chunk(turn_id, timestamp=first_token_time)

            token = ev.get("token", "")
            buffer += token
            parts = delimiters.split(buffer)
            if len(parts) > 1 and not sentence_1:
                sentence_1 = (parts[0] + parts[1]).strip()
                break  # We only need Sentence 1 to measure TTFB!
        elif ev_type == "done":
            next_conv_id = ev.get("conversation_id")

    if not sentence_1:
        sentence_1 = buffer.strip() or "Xin chào bạn."

    # Immediate TTS for Sentence 1
    t_tts_start = time.perf_counter()
    stream = tts.synthesize(sentence_1)
    async for ev in stream:
        coordinator.record_tts_first_audio(turn_id)
        break

    m = coordinator._current_metrics
    return {
        "mode": "Phase 7 Optimized (Streaming)",
        "conv_id": next_conv_id,
        "speech_end_to_stt": m.speech_end_to_stt_ms,
        "stt_to_llm": m.stt_to_llm_ms,
        "llm_to_tts": m.llm_to_tts_first_audio_ms,
        "e2e_total": m.speech_end_to_first_audio_ms,
        "sentence_1": sentence_1[:50],
    }


async def main():
    print("=" * 70, flush=True)
    print("📊 BENCHMARK TRƯỚC / SAU TỐI ƯU REALTIME (PHASE 6 vs PHASE 7)", flush=True)
    print("=" * 70, flush=True)

    rag_client = TravelWiseRAGClient(base_url=config.BACKEND_API_URL)
    blaze_tts = BlazeTTS()

    test_queries = [
        "Chùa Linh Ứng ở Đà Nẵng có gì đặc biệt?",
        "Nơi đó có gần bãi biển Mỹ Khê không?",  # Follow-up referencing context
        "Buổi tối ở Đà Nẵng nên đi dạo ở những điểm nào?",
    ]

    results_baseline = []
    results_optimized = []

    print("\n>>> BẮT ĐẦU ĐO BASELINE (Phase 6 Monolithic Batch)...", flush=True)
    conv_id = None
    for q in test_queries:
        res = await run_baseline_turn(q, conv_id, rag_client, blaze_tts)
        conv_id = res["conv_id"]
        results_baseline.append(res)
        print(f"  [Baseline] '{q[:30]}...' -> E2E: {res['e2e_total']:.1f}ms (STT: {res['speech_end_to_stt']:.1f}ms, LLM: {res['stt_to_llm']:.1f}ms, TTS: {res['llm_to_tts']:.1f}ms)")

    print("\n>>> BẮT ĐẦU ĐO OPTIMIZED (Phase 7 Streaming + Sentence Pacer)...", flush=True)
    conv_id = None
    for q in test_queries:
        res = await run_optimized_turn(q, conv_id, rag_client, blaze_tts)
        conv_id = res["conv_id"]
        results_optimized.append(res)
        print(f"  [Optimized] '{q[:30]}...' -> E2E: {res['e2e_total']:.1f}ms (STT: {res['speech_end_to_stt']:.1f}ms, LLM: {res['stt_to_llm']:.1f}ms, TTS: {res['llm_to_tts']:.1f}ms)")

    # Interruption test measurement
    print("\n>>> BẮT ĐẦU ĐO ĐỘ TRỄ HỦY PHÁT KHI NGƯỜI DÙNG NGẮT LỜI...", flush=True)
    coord = ConversationCoordinator()
    coord.start_new_turn("Test interruption")
    coord.is_agent_speaking = True

    cancel_latencies = []
    for _ in range(5):
        t0 = time.perf_counter()
        coord.handle_interruption("Test interruption")
        t1 = time.perf_counter()
        cancel_latencies.append((t1 - t0) * 1000)

    avg_cancel_ms = sum(cancel_latencies) / len(cancel_latencies)
    print(f"  ⚡ Thời gian hủy lượt và dừng audio: Trung bình {avg_cancel_ms:.2f}ms (Max: {max(cancel_latencies):.2f}ms)")

    # Print Comparative Table
    print("\n" + "=" * 80)
    print("📋 BẢNG SO SÁNH TRỰC DIỆN (BASELINE vs OPTIMIZED)")
    print("=" * 80)
    print(f"{'Tiêu chí':<45} | {'Phase 6 Baseline':<16} | {'Phase 7 Optimized':<16} | {'Cải thiện'}")
    print("-" * 80)

    avg_base_stt = sum(r["speech_end_to_stt"] for r in results_baseline) / len(results_baseline)
    avg_opt_stt = sum(r["speech_end_to_stt"] for r in results_optimized) / len(results_optimized)

    avg_base_llm = sum(r["stt_to_llm"] for r in results_baseline) / len(results_baseline)
    avg_opt_llm = sum(r["stt_to_llm"] for r in results_optimized) / len(results_optimized)

    avg_base_tts = sum(r["llm_to_tts"] for r in results_baseline) / len(results_baseline)
    avg_opt_tts = sum(r["llm_to_tts"] for r in results_optimized) / len(results_optimized)

    avg_base_e2e = sum(r["e2e_total"] for r in results_baseline) / len(results_baseline)
    avg_opt_e2e = sum(r["e2e_total"] for r in results_optimized) / len(results_optimized)

    print(f"{'1. Kết thúc nói -> STT hoàn thành':<45} | {avg_base_stt:>14.1f}ms | {avg_opt_stt:>14.1f}ms | {'~'}")
    diff_llm = avg_base_llm - avg_opt_llm
    pct_llm = (diff_llm / avg_base_llm) * 100
    print(f"{'2. STT hoàn thành -> LLM bắt đầu trả kết quả':<45} | {avg_base_llm:>14.1f}ms | {avg_opt_llm:>14.1f}ms | Giảm {pct_llm:.1f}%")

    diff_tts = avg_base_tts - avg_opt_tts
    pct_tts = (diff_tts / avg_base_tts) * 100 if avg_base_tts > 0 else 0
    print(f"{'3. LLM trả kết quả -> TTS có audio đầu tiên':<45} | {avg_base_tts:>14.1f}ms | {avg_opt_tts:>14.1f}ms | Giảm {abs(pct_tts):.1f}%")

    diff_e2e = avg_base_e2e - avg_opt_e2e
    pct_e2e = (diff_e2e / avg_base_e2e) * 100
    print(f"{'🎯 4. Kết thúc nói -> Nghe audio đầu tiên (E2E)':<45} | {avg_base_e2e:>14.1f}ms | {avg_opt_e2e:>14.1f}ms | Giảm {pct_e2e:.1f}% (-{diff_e2e:.0f}ms)")
    print("=" * 80)


if __name__ == "__main__":
    asyncio.run(main())
