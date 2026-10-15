"""
RAG Ingestion Script — TravelWise Knowledge Base.

Indexes all knowledge articles from SQL Server and crawled JSONL into Chroma vector database.
Uses deterministic IDs to update existing chunks without creating duplicates.

Usage:
    # Nạp tiếp các dữ liệu mới (Incremental - Mặc định nhanh & tiết kiệm API Quota):
    uv run python scripts/ingest_rag.py

    # Xóa sạch collection và nạp lại toàn bộ từ đầu:
    uv run python scripts/ingest_rag.py --reset
"""

import argparse
import os
import sys
from pathlib import Path

# Add project root (apps/api) to sys.path
api_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(api_root))

# Force UTF-8 on Windows stdout if possible
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

from sqlmodel import Session

from app.db.session import engine
from app.rag.config import (
    CHROMA_COLLECTION_NAME,
    CHROMA_PERSIST_DIRECTORY,
    EMBEDDING_MODEL,
    EMBEDDING_PROVIDER,
    RAG_CHUNK_OVERLAP,
    RAG_CHUNK_SIZE,
)
from app.rag.loader import load_crawled_documents, load_knowledge_documents
from app.rag.splitter import split_documents
from app.rag.vectorstore import generate_chunk_id, get_vectorstore, upsert_documents


def run_ingestion(reset: bool = False) -> None:
    """Execute the full knowledge ingestion pipeline (incremental by default, full reset if specified)."""
    print("=" * 60)
    print("TravelWise RAG Knowledge Ingestion")
    print("=" * 60)
    print(f"Collection        : {CHROMA_COLLECTION_NAME}")
    print(f"Persist Directory : {CHROMA_PERSIST_DIRECTORY}")
    print(f"Embedding Provider: {EMBEDDING_PROVIDER}")
    print(f"Embedding Model   : {EMBEDDING_MODEL}")
    print(f"Chunk Size        : {RAG_CHUNK_SIZE}")
    print(f"Chunk Overlap     : {RAG_CHUNK_OVERLAP}")
    print(f"Mode              : {'RESET (Xóa và nạp lại từ đầu)' if reset else 'INCREMENTAL (Chỉ nạp chunk mới)'}")
    print("-" * 60)

    # 1. Load documents from all sources
    print("[1/4] Reading knowledge from sources...")
    raw_documents = []

    # Source A: SQL Server
    try:
        with Session(engine) as session:
            sql_documents = load_knowledge_documents(session)
            print(f"      [✓] SQL Server : Loaded {len(sql_documents)} articles.")
            raw_documents.extend(sql_documents)
    except Exception as exc:
        print(f"      [!] SQL Server : Bỏ qua do kết nối DB không thành công ({type(exc).__name__}).")

    # Source B: Crawled JSONL
    try:
        crawled_documents = load_crawled_documents()
        if crawled_documents:
            print(f"      [✓] Crawl JSONL: Loaded {len(crawled_documents)} articles.")
            raw_documents.extend(crawled_documents)
        else:
            print("      [-] Crawl JSONL: Không tìm thấy file hoặc file trống.")
    except Exception as exc:
        print(f"      [!] Crawl JSONL: Lỗi đọc file ({exc}).")

    if not raw_documents:
        print("WARNING: No knowledge articles found from any source!")
        print("Vui lòng chạy crawler hoặc tạo dữ liệu mẫu trước.")
        return

    print(f"      ==> Tổng cộng: {len(raw_documents)} bài viết sẵn sàng để index.")

    # 2. Chunk documents
    print("\n[2/4] Splitting documents into chunks...")
    chunked_documents = split_documents(
        raw_documents,
        chunk_size=RAG_CHUNK_SIZE,
        chunk_overlap=RAG_CHUNK_OVERLAP,
    )
    print(f"      Created {len(chunked_documents)} chunks from {len(raw_documents)} articles.")

    # 3. Initialize Chroma vector store & handle incremental vs reset
    print("\n[3/4] Initializing Chroma vector store & checking existing chunks...")
    vectorstore = get_vectorstore()

    if reset:
        try:
            vectorstore._client.delete_collection(CHROMA_COLLECTION_NAME)
            print(f"      [✓] [RESET] Đã làm sạch collection cũ '{CHROMA_COLLECTION_NAME}'.")
        except Exception:
            pass

        # Re-initialize vectorstore instance
        import app.rag.vectorstore as vs_module
        vs_module._vectorstore_instance = None
        vectorstore = get_vectorstore()
        chunks_to_upsert = chunked_documents
        print(f"      [!] Chế độ RESET: Sẽ nạp toàn bộ {len(chunks_to_upsert)} chunks.")
    else:
        # Incremental mode: Get existing IDs from Chroma without fetching embeddings
        try:
            existing_data = vectorstore._collection.get(include=[])
            existing_ids = set(existing_data.get("ids", []))
        except Exception:
            existing_ids = set()

        chunks_to_upsert = [
            doc for doc in chunked_documents
            if generate_chunk_id(doc) not in existing_ids
        ]
        already_indexed_count = len(chunked_documents) - len(chunks_to_upsert)

        print(f"      [i] Tổng chunks tạo ra : {len(chunked_documents)}")
        print(f"      [✓] Đã có trong Chroma : {already_indexed_count} chunks (bỏ qua, không gọi lại API).")
        print(f"      [+] Cần nạp mới        : {len(chunks_to_upsert)} chunks.")

        if not chunks_to_upsert:
            print("\n" + "=" * 60)
            print("SUCCESS: Dữ liệu Chroma Vector Store đã hoàn toàn cập nhật!")
            print(f"Không có chunk mới nào cần nạp. Tiết kiệm 100% chi phí Embedding.")
            print("=" * 60)
            return

    # 4. Upsert chunks into Chroma
    print(f"\n[4/4] Upserting {len(chunks_to_upsert)} chunks into Chroma collection...")
    upserted_count = upsert_documents(chunks_to_upsert, vectorstore=vectorstore)

    print("\n" + "=" * 60)
    print("SUCCESS: RAG Ingestion Completed!")
    print(f"Total Knowledge Articles: {len(raw_documents)}")
    print(f"Total Chunks Upserted   : {upserted_count}")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TravelWise RAG Knowledge Ingestion")
    parser.add_argument(
        "--reset",
        "--force",
        action="store_true",
        help="Xóa sạch collection cũ trong Chroma và nạp lại toàn bộ từ đầu",
    )
    args = parser.parse_args()
    run_ingestion(reset=args.reset)
