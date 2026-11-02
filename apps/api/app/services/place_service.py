import math
from typing import List, Optional

from fastapi import HTTPException, status
from sqlmodel import Session, select

from sqlalchemy import case
from sqlalchemy.orm import selectinload

from app.db.base import _utcnow
from app.models.category import Category
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.schemas.place import PlaceCreate, PlaceImageCreate


class PlaceService:
    EARTH_RADIUS_KM = 6371.0088

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
    def get_nearby_places(
        session: Session,
        latitude: float,
        longitude: float,
        radius_km: float = 10,
        limit: int = 20,
    ) -> List[tuple[Place, float]]:
        angular_radius = radius_km / PlaceService.EARTH_RADIUS_KM
        latitude_radians = math.radians(latitude)
        latitude_delta = math.degrees(angular_radius)
        min_latitude = max(-90, latitude - latitude_delta)
        max_latitude = min(90, latitude + latitude_delta)

        if (
            min_latitude <= -90
            or max_latitude >= 90
            or angular_radius >= math.pi / 2
        ):
            longitude_delta = 180
        else:
            longitude_ratio = math.sin(angular_radius) / math.cos(latitude_radians)
            longitude_delta = math.degrees(math.asin(min(1, longitude_ratio)))

        statement = (
            select(Place)
            .where(
                Place.is_deleted == False,  # noqa: E712
                Place.latitude.is_not(None),
                Place.longitude.is_not(None),
                Place.latitude >= min_latitude,
                Place.latitude <= max_latitude,
            )
            .options(selectinload(Place.images))
        )

        if longitude_delta < 180:
            min_longitude = longitude - longitude_delta
            max_longitude = longitude + longitude_delta
            if min_longitude < -180:
                statement = statement.where(
                    (Place.longitude >= min_longitude + 360)
                    | (Place.longitude <= max_longitude)
                )
            elif max_longitude > 180:
                statement = statement.where(
                    (Place.longitude >= min_longitude)
                    | (Place.longitude <= max_longitude - 360)
                )
            else:
                statement = statement.where(
                    Place.longitude >= min_longitude,
                    Place.longitude <= max_longitude,
                )

        nearby_places: List[tuple[Place, float]] = []
        for place in session.exec(statement).all():
            place_latitude = math.radians(place.latitude)
            place_longitude = math.radians(place.longitude)
            latitude_difference = place_latitude - latitude_radians
            longitude_difference = math.radians(place.longitude - longitude)
            haversine = (
                math.sin(latitude_difference / 2) ** 2
                + math.cos(latitude_radians)
                * math.cos(place_latitude)
                * math.sin(longitude_difference / 2) ** 2
            )
            distance_km = (
                2
                * PlaceService.EARTH_RADIUS_KM
                * math.asin(math.sqrt(min(1, max(0, haversine))))
            )
            if distance_km <= radius_km:
                nearby_places.append((place, distance_km))

        nearby_places.sort(key=lambda result: (result[1], result[0].id or 0))
        return nearby_places[:limit]

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
        search_pattern = f"%{query}%"
        relevance = case(
            (Place.name.ilike(search_pattern), 0),
            (
                Place.description.ilike(search_pattern)
                | Place.address.ilike(search_pattern),
                1,
            ),
            (Category.name.ilike(search_pattern), 2),
            else_=3,
        )
        stmt = (
            select(Place)
            .where(Place.is_deleted == False)  # noqa: E712
            .join(Category, isouter=True)
            .options(selectinload(Place.images))
            .where(
                (Place.name.ilike(search_pattern))
                | (Place.address.ilike(search_pattern))
                | (Place.description.ilike(search_pattern))
                | (Category.name.ilike(search_pattern))
            )
            .order_by(relevance, Place.id)
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
