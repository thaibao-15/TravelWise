"""
RAG Retriever module — executes semantic search queries against Chroma.
Supports Hybrid Multi-source retrieval: guarantees relevant Database knowledge
while enriching with crawled web articles.
"""

from typing import Any, Dict, List, Optional, Tuple

from langchain_chroma import Chroma
from langchain_core.documents import Document

from app.rag.config import RAG_TOP_K
from app.rag.vectorstore import get_vectorstore


class RAGRetriever:
    """Service for retrieving knowledge chunks using semantic search with multi-source balancing."""

    def __init__(self, vectorstore: Optional[Chroma] = None):
        self.vectorstore = vectorstore or get_vectorstore()

    def _search_with_filter(
        self,
        query: str,
        k: int,
        filter_dict: Optional[Dict[str, Any]] = None,
        query_embedding: Optional[List[float]] = None,
    ) -> List[Tuple[Document, float]]:
        """Safe similarity search returning (Document, score) with optional metadata filter."""
        try:
            if query_embedding is not None and hasattr(
                self.vectorstore, "similarity_search_by_vector_with_relevance_scores"
            ):
                return self.vectorstore.similarity_search_by_vector_with_relevance_scores(
                    embedding=query_embedding,
                    k=k,
                    filter=filter_dict,
                )
            return self.vectorstore.similarity_search_with_relevance_scores(
                query=query,
                k=k,
                filter=filter_dict,
            )
        except Exception:
            try:
                if query_embedding is not None and hasattr(
                    self.vectorstore, "similarity_search_by_vector"
                ):
                    raw_results = self.vectorstore.similarity_search_by_vector(
                        embedding=query_embedding,
                        k=k,
                        filter=filter_dict,
                    )
                    return [(doc, 1.0) for doc in raw_results]
                raw_results = self.vectorstore.similarity_search_with_score(
                    query=query,
                    k=k,
                    filter=filter_dict,
                )
                return [
                    (doc, round(1.0 / (1.0 + max(0.0, float(dist))), 4))
                    for doc, dist in raw_results
                ]
            except Exception:
                return []

    def search(
        self,
        query: str,
        top_k: Optional[int] = None,
        prefer_database: bool = True,
    ) -> List[Dict[str, Any]]:
        """Perform balanced multi-source semantic similarity search.

        Guarantees that official database places are preserved while enriching with web crawl knowledge.

        Args:
            query: The user search query or question.
            top_k: Number of relevant chunks to retrieve (defaults to RAG_TOP_K).
            prefer_database: If True, balances chunks across SQL database and web crawl.

        Returns:
            List of dicts containing chunk content, relevance score, and enriched metadata.
        """
        k = top_k or RAG_TOP_K
        clean_query = (query or "").strip()
        if not clean_query:
            return []

        # Pre-compute query embedding once to avoid duplicate Google API embedding network calls
        query_embedding: Optional[List[float]] = None
        try:
            if hasattr(self.vectorstore, "_embedding_function") and hasattr(
                self.vectorstore._embedding_function, "embed_query"
            ):
                query_embedding = self.vectorstore._embedding_function.embed_query(clean_query)
        except Exception as e:
            logger.debug("Pre-computing query embedding failed, falling back to text search: %s", e)

        all_results_with_scores: List[Tuple[Document, float]] = []

        if prefer_database:
            # 1. Allocate slots: at least half (min 2) for Database, remainder for Crawl
            k_db = max(2, k // 2)
            k_crawl = k

            # Query Database chunks
            db_docs = self._search_with_filter(
                query=clean_query,
                k=k_db,
                filter_dict={"source": "TravelWise"},
                query_embedding=query_embedding,
            )

            # Query Crawled web chunks
            crawl_docs = self._search_with_filter(
                query=clean_query,
                k=k_crawl,
                filter_dict={"source_type": "crawl4ai"},
                query_embedding=query_embedding,
            )

            # Apply a boost (+0.05) to curated Database knowledge so it ranks high
            boosted_db_docs = [
                (doc, round(min(1.0, float(score) + 0.05), 4))
                for doc, score in db_docs
            ]

            # Merge and deduplicate by content prefix
            seen_texts = set()
            merged: List[Tuple[Document, float]] = []

            for doc, score in boosted_db_docs + crawl_docs:
                text_key = doc.page_content.strip()[:100]
                if text_key not in seen_texts:
                    seen_texts.add(text_key)
                    merged.append((doc, score))

            if merged:
                merged.sort(key=lambda x: x[1], reverse=True)
                all_results_with_scores = merged[:k]

        # Fallback to standard search if hybrid returned nothing
        if not all_results_with_scores:
            all_results_with_scores = self._search_with_filter(
                clean_query,
                k=k,
                query_embedding=query_embedding,
            )

        formatted_results: List[Dict[str, Any]] = []

        for doc, score in all_results_with_scores:
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
                        "source_type": doc.metadata.get("source_type", "database" if doc.metadata.get("source") == "TravelWise" else "crawl"),
                        "chunk_index": doc.metadata.get("chunk_index"),
                    },
                }
            )

        return formatted_results
