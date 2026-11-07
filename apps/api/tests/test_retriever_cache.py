"""
Tests for RAG Retriever embedding caching.
"""

import unittest
from unittest.mock import MagicMock

from app.rag.retriever import (
    RAGRetriever,
    _cached_embed_query,
    clear_query_embedding_cache,
    normalize_embedding_query,
)


class TestRetrieverEmbeddingCache(unittest.TestCase):
    """Verify that query embeddings are properly normalized and cached via LRU."""

    def setUp(self):
        clear_query_embedding_cache()

    def test_normalize_embedding_query(self):
        self.assertEqual(normalize_embedding_query("Chùa Linh Ứng?"), "chùa linh ứng")
        self.assertEqual(normalize_embedding_query("  Bà Nà Hills...  "), "bà nà hills")
        self.assertEqual(normalize_embedding_query("ĐÈO HẢI VÂN!"), "đèo hải vân")
        self.assertEqual(normalize_embedding_query(""), "")
        self.assertEqual(normalize_embedding_query(None), "")

    def test_embedding_cache_hit_and_normalization(self):
        mock_embedding_fn = MagicMock()
        mock_embedding_fn.embed_query.return_value = [0.1, 0.2, 0.3, 0.4]

        mock_vectorstore = MagicMock()
        mock_vectorstore._embedding_function = mock_embedding_fn
        mock_vectorstore.similarity_search_by_vector_with_relevance_scores.return_value = []
        mock_vectorstore.similarity_search_with_relevance_scores.return_value = []

        retriever = RAGRetriever(vectorstore=mock_vectorstore)

        # 1. First search: Cache Miss -> calls embed_query
        retriever.search("Chùa Linh Ứng?")
        self.assertEqual(mock_embedding_fn.embed_query.call_count, 1)

        # 2. Second search with different casing & whitespace & punctuation: Cache Hit -> does NOT call embed_query again
        retriever.search("  chùa linh ứng  ")
        self.assertEqual(mock_embedding_fn.embed_query.call_count, 1)

        retriever.search("CHÙA LINH ỨNG!")
        self.assertEqual(mock_embedding_fn.embed_query.call_count, 1)

        # 3. Different query: Cache Miss -> calls embed_query again
        retriever.search("Bà Nà Hills")
        self.assertEqual(mock_embedding_fn.embed_query.call_count, 2)

        cache_info = _cached_embed_query.cache_info()
        self.assertEqual(cache_info.hits, 2)
        self.assertEqual(cache_info.misses, 2)


if __name__ == "__main__":
    unittest.main()

