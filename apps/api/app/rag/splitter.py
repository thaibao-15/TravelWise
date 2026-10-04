"""
RAG Splitter — chunks LangChain Documents with RecursiveCharacterTextSplitter.
Preserves original document metadata and tracks chunk indices.
"""

from typing import List, Optional

from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter

from app.rag.config import RAG_CHUNK_OVERLAP, RAG_CHUNK_SIZE


def get_text_splitter(
    chunk_size: Optional[int] = None,
    chunk_overlap: Optional[int] = None,
) -> RecursiveCharacterTextSplitter:
    """Create a configured RecursiveCharacterTextSplitter instance."""
    return RecursiveCharacterTextSplitter(
        chunk_size=chunk_size or RAG_CHUNK_SIZE,
        chunk_overlap=chunk_overlap or RAG_CHUNK_OVERLAP,
        separators=["\n\n", "\n", ". ", " ", ""],
    )


def split_documents(
    documents: List[Document],
    chunk_size: Optional[int] = None,
    chunk_overlap: Optional[int] = None,
) -> List[Document]:
    """Split input documents into smaller chunks while preserving metadata.

    Assigns a deterministic `chunk_index` to each sub-chunk of every document.

    Args:
        documents: List of LangChain Document objects from the loader.
        chunk_size: Optional override for chunk size.
        chunk_overlap: Optional override for chunk overlap.

    Returns:
        List of chunked Document objects.
    """
    splitter = get_text_splitter(chunk_size=chunk_size, chunk_overlap=chunk_overlap)
    chunked_docs: List[Document] = []

    for doc in documents:
        splits = splitter.split_text(doc.page_content)
        for chunk_idx, text in enumerate(splits):
            meta = dict(doc.metadata)
            meta["chunk_index"] = chunk_idx

            chunked_docs.append(
                Document(
                    page_content=text,
                    metadata=meta,
                )
            )

    return chunked_docs
