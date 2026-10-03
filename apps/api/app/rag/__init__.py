"""
RAG (Retrieval-Augmented Generation) package for TravelWise.
Provides loader, splitter, embeddings, vectorstore, and retriever.
"""

from app.rag.chain import RAGChain, RAGChainError, ask_rag, get_rag_chain
from app.rag.embeddings import get_embeddings
from app.rag.llm import extract_response_text, get_chat_llm
from app.rag.loader import load_knowledge_documents
from app.rag.prompt import (
    format_docs,
    get_rag_prompt,
    rag_chat_prompt,
    rag_string_prompt,
)
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
    "get_chat_llm",
    "extract_response_text",
    "format_docs",
    "get_rag_prompt",
    "rag_chat_prompt",
    "rag_string_prompt",
    "RAGChain",
    "RAGChainError",
    "get_rag_chain",
    "ask_rag",
]
