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
