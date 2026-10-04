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

    Format: knowledge_{knowledge_id}_chunk_{chunk_index}
    """
    knowledge_id = doc.metadata.get("knowledge_id", "unknown")
    chunk_index = doc.metadata.get("chunk_index", fallback_index)
    return f"knowledge_{knowledge_id}_chunk_{chunk_index}"


def upsert_documents(
    documents: List[Document],
    vectorstore: Optional[Chroma] = None,
) -> int:
    """Upsert chunked documents into Chroma using deterministic IDs.

    Re-running this function updates existing chunks rather than creating duplicates.

    Args:
        documents: List of chunked Document objects.
        vectorstore: Optional Chroma instance.

    Returns:
        Number of documents upserted.
    """
    if not documents:
        return 0

    vs = vectorstore or get_vectorstore()

    ids = [generate_chunk_id(doc, idx) for idx, doc in enumerate(documents)]

    vs.add_documents(documents=documents, ids=ids)
    return len(documents)
