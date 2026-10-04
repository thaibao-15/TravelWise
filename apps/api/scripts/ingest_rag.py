"""
RAG Ingestion Script — TravelWise Knowledge Base.

Indexes all knowledge articles from SQL Server into Chroma vector database.
Uses deterministic IDs to update existing chunks without creating duplicates.

Usage:
    uv run python scripts/ingest_rag.py
    # or
    python scripts/ingest_rag.py
"""

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
from app.rag.loader import load_knowledge_documents
from app.rag.splitter import split_documents
from app.rag.vectorstore import get_vectorstore, upsert_documents


def run_ingestion() -> None:
    """Execute the full knowledge ingestion pipeline."""
    print("=" * 60)
    print("TravelWise RAG Knowledge Ingestion")
    print("=" * 60)
    print(f"Collection       : {CHROMA_COLLECTION_NAME}")
    print(f"Persist Directory: {CHROMA_PERSIST_DIRECTORY}")
    print(f"Embedding Provider: {EMBEDDING_PROVIDER}")
    print(f"Embedding Model  : {EMBEDDING_MODEL}")
    print(f"Chunk Size       : {RAG_CHUNK_SIZE}")
    print(f"Chunk Overlap    : {RAG_CHUNK_OVERLAP}")
    print("-" * 60)

    # 1. Load documents from SQL Server
    print("[1/4] Reading knowledge from SQL Server...")
    with Session(engine) as session:
        raw_documents = load_knowledge_documents(session)

    if not raw_documents:
        print("WARNING: No knowledge articles found in database!")
        print("Please run `seed.py` first to insert initial knowledge data.")
        return

    print(f"      Loaded {len(raw_documents)} knowledge articles.")
    for doc in raw_documents[:5]:
        place_name = doc.metadata.get("place_name") or "N/A"
        title = doc.metadata.get("title") or "Untitled"
        print(f"      - [Place: {place_name}] {title}")
    if len(raw_documents) > 5:
        print(f"      ... and {len(raw_documents) - 5} more articles.")

    # 2. Chunk documents
    print("\n[2/4] Splitting documents into chunks...")
    chunked_documents = split_documents(
        raw_documents,
        chunk_size=RAG_CHUNK_SIZE,
        chunk_overlap=RAG_CHUNK_OVERLAP,
    )
    print(f"      Created {len(chunked_documents)} chunks from {len(raw_documents)} articles.")

    # 3. Initialize Chroma vector store
    print("\n[3/4] Initializing Chroma vector store & embeddings...")
    vectorstore = get_vectorstore()

    # 4. Upsert chunks into Chroma
    print("\n[4/4] Upserting chunks into Chroma collection...")
    upserted_count = upsert_documents(chunked_documents, vectorstore=vectorstore)

    print("\n" + "=" * 60)
    print("SUCCESS: RAG Ingestion Completed!")
    print(f"Total Knowledge Articles: {len(raw_documents)}")
    print(f"Total Chunks Upserted   : {upserted_count}")
    print("=" * 60)


if __name__ == "__main__":
    run_ingestion()
