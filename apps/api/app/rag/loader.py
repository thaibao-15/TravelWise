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
        select(Knowledge, Place.name.label("place_name"))
        .join(Place, Knowledge.place_id == Place.id, isouter=True)
    )

    if place_id is not None:
        statement = statement.where(Knowledge.place_id == place_id)

    results = session.exec(statement).all()
    documents: List[Document] = []

    for knowledge, place_name in results:
        content = knowledge.content or ""
        # Include title in page_content to maximize semantic search quality
        if knowledge.title:
            page_content = f"{knowledge.title}\n{content}".strip()
        else:
            page_content = content

        metadata = {
            "knowledge_id": knowledge.id,
            "place_id": knowledge.place_id,
            "place_name": place_name or "",
            "title": knowledge.title or "",
            "source": knowledge.source or "",
        }

        documents.append(
            Document(
                page_content=page_content,
                metadata=metadata,
            )
        )

    return documents
