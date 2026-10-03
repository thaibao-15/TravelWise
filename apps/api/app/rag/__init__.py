"""
RAG (Retrieval-Augmented Generation) package for TravelWise.
Provides loader, splitter, embeddings, vectorstore, and retriever.
"""

from app.rag.embeddings import get_embeddings
from app.rag.loader import load_knowledge_documents
from app.rag.retriever import RAGRetriever
from app.rag.splitter import split_documents
from app.rag.vectorstore import get_vectorstore, upsert_documents

__all__ = [
    "load_knowledge_documents",
    "split_documents",
    "get_embeddings",
    "get_vectorstore",
    "upsert_documents",
    "RAGRetriever",
]
