from typing import List, Optional

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.db.base import _utcnow
from app.models.place import Place
from app.schemas.place import PlaceCreate


class PlaceService:
    @staticmethod
    def list_places(
        session: Session,
        category_id: Optional[int] = None,
        skip: int = 0,
        limit: int = 50,
    ) -> List[Place]:
        statement = select(Place).where(Place.is_deleted == False).order_by(Place.id)  # noqa: E712
        if category_id is not None:
            statement = statement.where(Place.category_id == category_id)
        statement = statement.offset(skip).limit(limit)
        return list(session.exec(statement).all())

    @staticmethod
    def get_place_by_id(session: Session, place_id: int) -> Place:
        place = session.get(Place, place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Place with id {place_id} not found",
            )
        return place

    @staticmethod
    def create_place(session: Session, data: PlaceCreate) -> Place:
        place = Place(
            name=data.name,
            description=data.description,
            address=data.address,
            latitude=data.latitude,
            longitude=data.longitude,
            category_id=data.category_id,
        )
        session.add(place)
        session.commit()
        session.refresh(place)
        return place
