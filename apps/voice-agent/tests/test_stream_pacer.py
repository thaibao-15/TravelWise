"""Test script to measure sentence-level streaming latency from Gemini RAG."""

import asyncio
import re
import sys
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from services.rag_client import TravelWiseRAGClient


async def test_sentence_streaming():
    client = TravelWiseRAGClient()
    start = time.perf_counter()
    first_sentence_time = None
    buffer = ""
    sentences = []

    delimiters = re.compile(r"([.!?]+(?:\s+|$))")

    async for ev in client.ask_stream("Chùa Linh Ứng ở Đà Nẵng có gì đặc biệt?", mode="voice"):
        if ev.get("type") == "token":
            token = ev.get("token", "")
            buffer += token
            parts = delimiters.split(buffer)
            if len(parts) > 1:
                sentence = (parts[0] + parts[1]).strip()
                buffer = "".join(parts[2:])
                if sentence:
                    if first_sentence_time is None:
                        first_sentence_time = time.perf_counter()
                        latency = (first_sentence_time - start) * 1000
                        print(f"⚡ Sentence 1 ready at {latency:.1f}ms: '{sentence}'", flush=True)
                    sentences.append(sentence)

    if buffer.strip():
        sentences.append(buffer.strip())

    total_time = (time.perf_counter() - start) * 1000
    print(f"Total sentences: {len(sentences)}, Total LLM time: {total_time:.1f}ms", flush=True)
    for idx, s in enumerate(sentences, 1):
        print(f"  [{idx}] {s}", flush=True)


if __name__ == "__main__":
    asyncio.run(test_sentence_streaming())
