"""
RAG Loader — loads knowledge records from SQL Server.
Converts records into LangChain Document objects joined with place details.
"""

from typing import List, Optional

from langchain_core.documents import Document
from sqlmodel import Session, select

from app.models.knowledge import Knowledge
from app.models.place import Place


def load_knowledge_documents(
    session: Session,
    place_id: Optional[int] = None,
) -> List[Document]:
    """Read knowledge articles from SQL Server and convert to LangChain Documents.

    Joins with the `places` table to enrich metadata with the place name.

    Args:
        session: Active SQLModel database session.
        place_id: Optional filter for a specific place.

    Returns:
        List of LangChain Document objects ready for splitting and embedding.
    """
    statement = (
        select(Knowledge, Place)
        .join(Place, Knowledge.place_id == Place.id, isouter=True)
    )

    if place_id is not None:
        statement = statement.where(Knowledge.place_id == place_id)

    results = session.exec(statement).all()
    documents: List[Document] = []

    for knowledge, place in results:
        content = knowledge.content or ""

        # Enrich page_content with place name, address, and knowledge title
        header_parts = []
        if place and place.name:
            header_parts.append(f"Địa điểm: {place.name}")
        if place and place.address:
            header_parts.append(f"Địa chỉ: {place.address}")
        if knowledge.title:
            header_parts.append(f"Chủ đề: {knowledge.title}")

        header_str = " | ".join(header_parts)
        if header_str:
            page_content = f"[{header_str}]\n{content}".strip()
        else:
            page_content = content

        metadata = {
            "knowledge_id": knowledge.id,
            "place_id": knowledge.place_id or 0,
            "place_name": place.name if place else "",
            "place_address": place.address if (place and place.address) else "",
            "title": knowledge.title or "",
            "source": knowledge.source or "",
        }

        # Add optional location coordinates if available
        if place and place.latitude is not None:
            metadata["latitude"] = float(place.latitude)
        if place and place.longitude is not None:
            metadata["longitude"] = float(place.longitude)

        documents.append(
            Document(
                page_content=page_content,
                metadata=metadata,
            )
        )

    return documents


def load_crawled_documents(
    file_path: Optional[str] = None,
    min_length: int = 150,
) -> List[Document]:
    """Read crawled articles from a JSONL file and convert to LangChain Documents.

    Args:
        file_path: Optional path to the JSONL file. Defaults to `apps/api/data/crawled_pages.jsonl`.
        min_length: Minimum character length for article content to filter out trivial pages.

    Returns:
        List of LangChain Document objects.
    """
    import hashlib
    import json
    import os
    from pathlib import Path

    if file_path:
        target_path = Path(file_path)
    else:
        # Check environment variable first
        env_path = os.getenv("CRAWLED_PAGES_PATH")
        if env_path and Path(env_path).exists():
            target_path = Path(env_path)
        else:
            # Default to apps/api/data/crawled_pages.jsonl
            base_dir = Path(__file__).resolve().parent.parent.parent
            target_path = base_dir / "data" / "crawled_pages.jsonl"
            
            # Fallback to Blazer Intern/crawl/data/crawled_pages.jsonl if default doesn't exist
            if not target_path.exists():
                fallback_crawl_path = Path(r"e:\Blazer Intern\crawl\data\crawled_pages.jsonl")
                if fallback_crawl_path.exists():
                    target_path = fallback_crawl_path

    if not target_path.exists():
        return []

    documents: List[Document] = []

    with target_path.open("r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue

            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            content = (record.get("content") or "").strip()
            if len(content) < min_length:
                continue

            url = (record.get("url") or "").strip()
            title = (record.get("title") or "").strip()

            header_parts = []
            if title:
                header_parts.append(f"Chủ đề: {title}")
            if url:
                header_parts.append(f"Nguồn: {url}")

            header_str = " | ".join(header_parts)
            if header_str:
                page_content = f"[{header_str}]\n{content}".strip()
            else:
                page_content = content

            url_hash = (
                hashlib.md5(url.encode("utf-8")).hexdigest()[:10]
                if url
                else f"line_{line_num}"
            )

            metadata = {
                "source_type": "crawl4ai",
                "doc_id": f"crawl_{url_hash}",
                "title": title,
                "source": url,
                "date": record.get("date") or "",
                "description": record.get("description") or "",
                "crawled_at": record.get("crawled_at") or "",
            }

            documents.append(
                Document(
                    page_content=page_content,
                    metadata=metadata,
                )
            )

    return documents
