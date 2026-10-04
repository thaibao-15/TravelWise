from typing import List

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.models.knowledge import Knowledge
from app.models.place import Place
from app.schemas.knowledge import KnowledgeCreate


class KnowledgeService:
    @staticmethod
    def get_knowledge_by_id(session: Session, knowledge_id: int) -> Knowledge:
        knowledge = session.get(Knowledge, knowledge_id)
        if not knowledge:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Knowledge with id {knowledge_id} not found",
            )
        return knowledge

    @staticmethod
    def get_knowledge_by_place(session: Session, place_id: int) -> List[Knowledge]:
        # Verify place exists
        place = session.get(Place, place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Place with id {place_id} not found",
            )
        statement = select(Knowledge).where(Knowledge.place_id == place_id)
        return list(session.exec(statement).all())

    @staticmethod
    def create_knowledge(session: Session, data: KnowledgeCreate) -> Knowledge:
        # Verify place exists
        place = session.get(Place, data.place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Place with id {data.place_id} not found",
            )
        knowledge = Knowledge(
            place_id=data.place_id,
            title=data.title,
            content=data.content,
            source=data.source,
        )
        session.add(knowledge)
        session.commit()
        session.refresh(knowledge)
        return knowledge
