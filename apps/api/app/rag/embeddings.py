"""
Embedding model abstraction for TravelWise RAG pipeline.

Supports:
- OpenAIEmbeddings (when OPENAI_API_KEY is configured or provider="openai")
- ChromaDefaultEmbeddings (local ONNX all-MiniLM-L6-v2, no API key required)

Does not hardcode providers into business logic.
"""

import logging
from typing import List, Optional

from chromadb.utils import embedding_functions
from langchain_core.embeddings import Embeddings

from app.rag.config import (
    EMBEDDING_MODEL,
    EMBEDDING_PROVIDER,
    OPENAI_API_KEY,
)

logger = logging.getLogger(__name__)


class ChromaDefaultEmbeddings(Embeddings):
    """LangChain Embeddings wrapper around Chroma's DefaultEmbeddingFunction.

    Runs locally using ONNX runtime and all-MiniLM-L6-v2 without requiring
    an external API key or network connection.
    """

    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        self.model_name = model_name
        self._ef = embedding_functions.DefaultEmbeddingFunction()

    def embed_documents(self, texts: List[str]) -> List[List[float]]:
        """Embed a list of document strings."""
        return self._ef(texts)

    def embed_query(self, text: str) -> List[float]:
        """Embed a single query string."""
        return self._ef([text])[0]


_embeddings_instance: Optional[Embeddings] = None


def get_embeddings() -> Embeddings:
    """Factory function returning a configured LangChain Embeddings instance.

    Selection strategy:
    1. If EMBEDDING_PROVIDER == "openai":
       Requires OPENAI_API_KEY; uses LangChain's OpenAIEmbeddings.
    2. If EMBEDDING_PROVIDER == "auto":
       If OPENAI_API_KEY is available -> uses OpenAIEmbeddings.
       Otherwise -> falls back cleanly to local ChromaDefaultEmbeddings.
    3. If EMBEDDING_PROVIDER == "local" or "default":
       Uses ChromaDefaultEmbeddings.
    """
    global _embeddings_instance
    if _embeddings_instance is not None:
        return _embeddings_instance

    provider = (EMBEDDING_PROVIDER or "auto").lower()

    if provider == "openai" or (provider == "auto" and OPENAI_API_KEY):
        if not OPENAI_API_KEY:
            raise ValueError(
                "OPENAI_API_KEY must be set in environment when EMBEDDING_PROVIDER is 'openai'."
            )
        from langchain_openai import OpenAIEmbeddings

        logger.info("Initializing OpenAIEmbeddings with model: %s", EMBEDDING_MODEL)
        _embeddings_instance = OpenAIEmbeddings(
            model=EMBEDDING_MODEL,
            api_key=OPENAI_API_KEY,
        )
    else:
        logger.info("Initializing local ChromaDefaultEmbeddings (ONNX all-MiniLM-L6-v2)")
        _embeddings_instance = ChromaDefaultEmbeddings()

    return _embeddings_instance
