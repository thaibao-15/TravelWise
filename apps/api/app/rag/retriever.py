"""
RAG Retriever module — executes semantic search queries against Chroma.
Returns top-K relevant chunks with similarity/relevance scores and metadata.
"""

from typing import Any, Dict, List, Optional

from langchain_chroma import Chroma

from app.rag.config import RAG_TOP_K
from app.rag.vectorstore import get_vectorstore


class RAGRetriever:
    """Service for retrieving knowledge chunks using semantic search."""

    def __init__(self, vectorstore: Optional[Chroma] = None):
        self.vectorstore = vectorstore or get_vectorstore()

    def search(
        self,
        query: str,
        top_k: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """Perform semantic similarity search on knowledge base.

        Args:
            query: The user search query or question.
            top_k: Number of relevant chunks to retrieve (defaults to RAG_TOP_K).

        Returns:
            List of dicts, each containing:
                - content: Text of the matched chunk
                - score: Relevance score (float, higher is more relevant)
                - metadata: Metadata dictionary (place_id, knowledge_id, etc.)
        """
        k = top_k or RAG_TOP_K
        if not query or not query.strip():
            return []

        # similarity_search_with_relevance_scores returns (Document, score)
        # where score is normalized (higher = more similar)
        try:
            results_with_scores = (
                self.vectorstore.similarity_search_with_relevance_scores(
                    query=query.strip(),
                    k=k,
                )
            )
        except Exception:
            # Fallback to similarity_search_with_score if relevance score conversion fails
            raw_results = self.vectorstore.similarity_search_with_score(
                query=query.strip(),
                k=k,
            )
            # Distance: convert to pseudo relevance score (1 / (1 + distance))
            results_with_scores = [
                (doc, round(1.0 / (1.0 + max(0.0, float(dist))), 4))
                for doc, dist in raw_results
            ]

        formatted_results: List[Dict[str, Any]] = []

        for doc, score in results_with_scores:
            formatted_results.append(
                {
                    "content": doc.page_content,
                    "score": round(float(score), 4),
                    "metadata": {
                        "knowledge_id": doc.metadata.get("knowledge_id"),
                        "place_id": doc.metadata.get("place_id"),
                        "place_name": doc.metadata.get("place_name"),
                        "place_address": doc.metadata.get("place_address"),
                        "latitude": doc.metadata.get("latitude"),
                        "longitude": doc.metadata.get("longitude"),
                        "title": doc.metadata.get("title"),
                        "source": doc.metadata.get("source"),
                        "chunk_index": doc.metadata.get("chunk_index"),
                    },
                }
            )

        return formatted_results
