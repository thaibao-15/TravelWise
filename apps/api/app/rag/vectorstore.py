"""
Chroma Vector Store management for TravelWise knowledge base.

Handles persistent collection loading, deterministic ID generation,
and idempotent document upsertion.
"""

import os
from pathlib import Path
from typing import List, Optional

from langchain_chroma import Chroma
from langchain_core.documents import Document

from app.rag.config import (
    CHROMA_COLLECTION_NAME,
    CHROMA_PERSIST_DIRECTORY,
)
from app.rag.embeddings import get_embeddings


def get_persist_path() -> str:
    """Resolve the Chroma persistent storage path and ensure the directory exists."""
    path = Path(CHROMA_PERSIST_DIRECTORY)
    if not path.is_absolute():
        # Resolve relative to the apps/api directory
        base_dir = Path(__file__).resolve().parent.parent.parent
        path = base_dir / path
    path.mkdir(parents=True, exist_ok=True)
    return str(path)


_vectorstore_instance: Optional[Chroma] = None


def get_vectorstore(collection_name: Optional[str] = None) -> Chroma:
    """Get or create the persistent Chroma vector store instance."""
    global _vectorstore_instance

    col_name = collection_name or CHROMA_COLLECTION_NAME
    persist_dir = get_persist_path()
    embeddings = get_embeddings()

    if _vectorstore_instance is None:
        _vectorstore_instance = Chroma(
            collection_name=col_name,
            embedding_function=embeddings,
            persist_directory=persist_dir,
        )

    return _vectorstore_instance


def generate_chunk_id(doc: Document, fallback_index: int = 0) -> str:
    """Generate a deterministic ID for a chunk to prevent duplicates on re-ingestion.

    Supports both SQL Server knowledge records and crawled JSONL documents.
    """
    chunk_index = doc.metadata.get("chunk_index", fallback_index)

    # 1. SQL Server knowledge
    if "knowledge_id" in doc.metadata and doc.metadata["knowledge_id"] != "unknown":
        return f"knowledge_{doc.metadata['knowledge_id']}_chunk_{chunk_index}"

    # 2. Crawled document with doc_id
    if "doc_id" in doc.metadata:
        return f"{doc.metadata['doc_id']}_chunk_{chunk_index}"

    # 3. Fallback deterministic hash
    source_key = doc.metadata.get("source") or str(fallback_index)
    import hashlib
    safe_key = hashlib.md5(source_key.encode("utf-8")).hexdigest()[:8]
    return f"doc_{safe_key}_chunk_{chunk_index}"


def upsert_documents(
    documents: List[Document],
    vectorstore: Optional[Chroma] = None,
    batch_size: int = 500,
) -> int:
    """Upsert chunked documents into Chroma using deterministic IDs in batches.

    Re-running this function updates existing chunks rather than creating duplicates.
    Processes items in batches to respect ChromaDB's maximum batch size limit (5,461).

    Args:
        documents: List of chunked Document objects.
        vectorstore: Optional Chroma instance.
        batch_size: Number of documents per batch (default: 500).

    Returns:
        Number of documents upserted.
    """
    if not documents:
        return 0

    vs = vectorstore or get_vectorstore()

    ids = [generate_chunk_id(doc, idx) for idx, doc in enumerate(documents)]
    total = len(documents)
    total_batches = (total + batch_size - 1) // batch_size

    for batch_idx in range(total_batches):
        start = batch_idx * batch_size
        end = min(start + batch_size, total)
        batch_docs = documents[start:end]
        batch_ids = ids[start:end]

        vs.add_documents(documents=batch_docs, ids=batch_ids)
        print(f"      [Chroma] Tiến độ: {end:,}/{total:,} chunks ({((end / total) * 100):.1f}%)...")

    return total
