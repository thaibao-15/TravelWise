from typing import List, Optional

from fastapi import HTTPException, status
from sqlmodel import Session, select

from sqlalchemy.orm import selectinload

from app.db.base import _utcnow
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.schemas.place import PlaceCreate, PlaceImageCreate


class PlaceService:
    @staticmethod
    def list_places(
        session: Session,
        category_id: Optional[int] = None,
        skip: int = 0,
        limit: int = 50,
    ) -> List[Place]:
        statement = (
            select(Place)
            .where(Place.is_deleted == False)  # noqa: E712
            .options(selectinload(Place.images))
            .order_by(Place.id)
        )
        if category_id is not None:
            statement = statement.where(Place.category_id == category_id)
        statement = statement.offset(skip).limit(limit)
        return list(session.exec(statement).all())

    @staticmethod
    def get_places_by_category(
        session: Session,
        category_id: int,
        skip: int = 0,
        limit: int = 50,
    ) -> List[Place]:
        return PlaceService.list_places(
            session, category_id=category_id, skip=skip, limit=limit
        )

    @staticmethod
    def get_place_by_id(session: Session, place_id: int) -> Place:
        statement = (
            select(Place)
            .where(Place.id == place_id, Place.is_deleted == False)  # noqa: E712
            .options(
                selectinload(Place.images),
                selectinload(Place.restaurant_detail),
                selectinload(Place.hotel_detail),
            )
        )
        place = session.exec(statement).first()
        if not place:
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

    @staticmethod
    def search_places_by_keyword(
        session: Session,
        query: str,
        skip: int = 0,
        limit: int = 20,
    ) -> List[Place]:
        stmt = (
            select(Place)
            .where(Place.is_deleted == False)  # noqa: E712
            .options(selectinload(Place.images))
            .where(
                (Place.name.ilike(f"%{query}%"))
                | (Place.address.ilike(f"%{query}%"))
                | (Place.description.ilike(f"%{query}%"))
            )
            .order_by(Place.id)
            .offset(skip)
            .limit(limit)
        )
        return list(session.exec(stmt).all())

    @staticmethod
    def add_image_to_place(session: Session, place_id: int, data: PlaceImageCreate) -> PlaceImage:
        place = session.get(Place, place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Place with id {place_id} not found",
            )

        # If this image is marked as primary, reset existing primary images
        if data.is_primary:
            existing_primary_imgs = session.exec(
                select(PlaceImage).where(
                    PlaceImage.place_id == place_id,
                    PlaceImage.is_primary == True,  # noqa: E712
                )
            ).all()
            for img in existing_primary_imgs:
                img.is_primary = False
                session.add(img)

        image = PlaceImage(
            place_id=place_id,
            url=data.url,
            description=data.description,
            is_primary=data.is_primary,
        )
        session.add(image)
        session.commit()
        session.refresh(image)
        return image
