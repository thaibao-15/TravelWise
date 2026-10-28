import json
import logging
from pathlib import Path
from typing import Any, Optional

from sqlalchemy import inspect, text
from sqlmodel import Session, select

from app.models.category import Category
from app.models.hotel_detail import HotelDetail
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.schemas.osm_hotel import NormalizedHotel

logger = logging.getLogger(__name__)


class OSMHotelImporterService:
    """Service to import normalized OpenStreetMap hotel records into SQL Server."""

    @staticmethod
    def ensure_schema(session: Session) -> None:
        """Ensure source, osm_type, osm_id in places and new hotel_details columns exist."""
        bind = session.get_bind()
        insp = inspect(bind)
        cols = [c["name"] for c in insp.get_columns("places")]

        dialect_name = bind.dialect.name
        if dialect_name == "mssql":
            with bind.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
                if "source" not in cols:
                    conn.execute(text("ALTER TABLE places ADD source NVARCHAR(50) NULL"))
                if "osm_type" not in cols:
                    conn.execute(text("ALTER TABLE places ADD osm_type NVARCHAR(20) NULL"))
                if "osm_id" not in cols:
                    conn.execute(text("ALTER TABLE places ADD osm_id BIGINT NULL"))

                indexes = [idx["name"] for idx in insp.get_indexes("places")]
                if "uq_places_osm_type_id" not in indexes:
                    conn.execute(text(
                        "CREATE UNIQUE NONCLUSTERED INDEX uq_places_osm_type_id "
                        "ON places (osm_type, osm_id) "
                        "WHERE osm_id IS NOT NULL"
                    ))

                # Ensure hotel_details columns exist
                hotel_cols = [c["name"] for c in insp.get_columns("hotel_details")]
                if "phone" not in hotel_cols:
                    conn.execute(text("ALTER TABLE hotel_details ADD phone NVARCHAR(50) NULL"))
                if "website" not in hotel_cols:
                    conn.execute(text("ALTER TABLE hotel_details ADD website NVARCHAR(500) NULL"))
                if "email" not in hotel_cols:
                    conn.execute(text("ALTER TABLE hotel_details ADD email NVARCHAR(255) NULL"))
                if "rooms" not in hotel_cols:
                    conn.execute(text("ALTER TABLE hotel_details ADD rooms INT NULL"))
                if "beds" not in hotel_cols:
                    conn.execute(text("ALTER TABLE hotel_details ADD beds INT NULL"))

    @staticmethod
    def get_hotel_category(session: Session) -> Category:
        """Find existing hotel/accommodation category to prevent duplicate category creation.

        Prioritizes existing categories named 'Lưu trú và nghỉ dưỡng', 'Khách sạn', 'Hotel', etc.
        """
        all_categories = list(session.exec(select(Category)).all())
        for c in all_categories:
            if not c.name:
                continue
            name_lower = c.name.strip().lower()
            if any(kw in name_lower for kw in ("lưu trú", "khách sạn", "hotel", "resort", "lodging", "nghỉ dưỡng")):
                return c

        # Fallback only if no accommodation category exists in the system
        new_cat = Category(
            name="Lưu trú và nghỉ dưỡng",
            description="Khách sạn, resort, homestay và căn hộ du lịch.",
        )
        session.add(new_cat)
        session.flush()
        return new_cat

    @staticmethod
    def update_geography_location(
        session: Session,
        place_id: int,
        lat: Optional[float],
        lon: Optional[float],
    ) -> None:
        """Update SQL Server GEOGRAPHY spatial column using correct (lat, lon, 4326) order."""
        if lat is None or lon is None:
            return

        bind = session.get_bind()
        if bind.dialect.name == "mssql":
            session.execute(
                text("UPDATE places SET location = geography::Point(:lat, :lon, 4326) WHERE id = :id"),
                {"lat": lat, "lon": lon, "id": place_id},
            )

    @classmethod
    def import_single_hotel(
        cls,
        session: Session,
        item: dict[str, Any],
        category_id: int,
        dry_run: bool = False,
    ) -> str:
        """Import or update a single normalized hotel record.

        Returns:
            "added" if a new place was inserted (or projected in dry-run).
            "updated" if an existing place was updated (or projected in dry-run).
            "skipped" if mandatory fields are missing.
        """
        osm_id = item.get("osm_id")
        osm_type = item.get("osm_type")
        name = item.get("name")

        if not osm_id or not osm_type or not name or not str(name).strip():
            return "skipped"

        name = str(name).strip()
        lat = item.get("latitude")
        lon = item.get("longitude")
        address = item.get("address")
        star_rating = item.get("star_rating")
        amenities = item.get("amenities") or []
        amenities_str = ", ".join(amenities) if amenities else None
        image_url = item.get("image_url")
        phone = item.get("phone")
        website = item.get("website")
        email = item.get("email")
        rooms = item.get("rooms")
        beds = item.get("beds")

        has_hotel_details = any([
            star_rating is not None,
            amenities_str,
            phone,
            website,
            email,
            rooms is not None,
            beds is not None,
        ])

        # 1. Deduplication lookup strictly by (osm_type, osm_id)
        existing_place = session.exec(
            select(Place).where(
                Place.osm_type == osm_type,
                Place.osm_id == osm_id,
            )
        ).first()

        # In dry-run mode, strictly evaluate projection without executing INSERT or UPDATE
        if dry_run:
            return "added" if existing_place is None else "updated"

        if existing_place is None:
            # ─── INSERT NEW PLACE ──────────────────────────────────────────
            place = Place(
                name=name,
                address=address,
                latitude=lat,
                longitude=lon,
                category_id=category_id,
                source="osm",
                osm_type=osm_type,
                osm_id=osm_id,
                is_deleted=False,
            )
            session.add(place)
            session.flush()

            # Set spatial geography in SQL Server
            cls.update_geography_location(session, place.id, lat, lon)

            # Insert HotelDetail if any hotel attributes exist
            if has_hotel_details:
                detail = HotelDetail(
                    place_id=place.id,
                    star_rating=star_rating,
                    amenities=amenities_str,
                    price_per_night=None,  # Never invent unverified pricing
                    phone=phone,
                    website=website,
                    email=email,
                    rooms=rooms,
                    beds=beds,
                )
                session.add(detail)

            # Insert PlaceImage if valid URL exists
            if image_url:
                img = PlaceImage(
                    place_id=place.id,
                    url=image_url,
                    is_primary=True,
                    description=f"Ảnh từ OpenStreetMap cho {name}",
                )
                session.add(img)

            return "added"

        else:
            # ─── UPDATE EXISTING PLACE (Preserve manual input & is_deleted) ───
            # Rule: Do not overwrite verified/manual information with null or empty from OSM
            # Rule: Do not alter is_deleted flag
            if not existing_place.source or existing_place.source == "osm":
                existing_place.name = name

            if address and str(address).strip():
                existing_place.address = address.strip()

            if lat is not None and lon is not None:
                existing_place.latitude = lat
                existing_place.longitude = lon
                cls.update_geography_location(session, existing_place.id, lat, lon)

            if existing_place.category_id is None:
                existing_place.category_id = category_id

            if not existing_place.source:
                existing_place.source = "osm"

            session.add(existing_place)

            # Update HotelDetail
            detail = session.get(HotelDetail, existing_place.id)
            if detail:
                if star_rating is not None:
                    detail.star_rating = star_rating
                if amenities_str:
                    detail.amenities = amenities_str
                if phone:
                    detail.phone = phone
                if website:
                    detail.website = website
                if email:
                    detail.email = email
                if rooms is not None:
                    detail.rooms = rooms
                if beds is not None:
                    detail.beds = beds
                # detail.price_per_night is intentionally UNTOUCHED to preserve manual/admin pricing!
                session.add(detail)
            elif has_hotel_details:
                detail = HotelDetail(
                    place_id=existing_place.id,
                    star_rating=star_rating,
                    amenities=amenities_str,
                    price_per_night=None,
                    phone=phone,
                    website=website,
                    email=email,
                    rooms=rooms,
                    beds=beds,
                )
                session.add(detail)

            # Update PlaceImage
            if image_url:
                existing_img = session.exec(
                    select(PlaceImage).where(
                        PlaceImage.place_id == existing_place.id,
                        PlaceImage.url == image_url,
                    )
                ).first()
                if not existing_img:
                    session.add(
                        PlaceImage(
                            place_id=existing_place.id,
                            url=image_url,
                            is_primary=True,
                            description=f"Ảnh từ OpenStreetMap cho {existing_place.name}",
                        )
                    )

            return "updated"

    @classmethod
    def import_normalized_hotels(
        cls,
        session: Session,
        records: list[dict[str, Any]],
        limit: Optional[int] = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Import a list of normalized hotel records with transaction safety and detailed metrics."""
        # Ensure source, osm_type, osm_id columns and filtered unique index exist
        cls.ensure_schema(session)

        category = cls.get_hotel_category(session)
        category_id = category.id

        if limit is not None and limit > 0:
            records = records[:limit]

        added_count = 0
        updated_count = 0
        skipped_count = 0
        error_count = 0
        errors: list[str] = []

        logger.info(
            "Starting OSM hotel import: %d records, Category '%s' (id=%s), dry_run=%s",
            len(records),
            category.name,
            category_id,
            dry_run,
        )

        for idx, item in enumerate(records, 1):
            try:
                if dry_run:
                    res = cls.import_single_hotel(session, item, category_id, dry_run=True)
                else:
                    # Use sub-transactions (savepoints) so one record failure does not abort the batch
                    with session.begin_nested():
                        res = cls.import_single_hotel(session, item, category_id, dry_run=False)

                if res == "added":
                    added_count += 1
                elif res == "updated":
                    updated_count += 1
                else:
                    skipped_count += 1
            except Exception as exc:
                error_count += 1
                err_msg = f"Error importing OSM hotel {item.get('osm_type')}/{item.get('osm_id')}: {exc}"
                logger.warning(err_msg)
                errors.append(err_msg)

        if dry_run:
            session.rollback()
            logger.info("Dry-run mode: Transaction rolled back without saving changes.")
        else:
            session.commit()
            logger.info("Import committed successfully to database.")

        return {
            "total_records": len(records),
            "added_count": added_count,
            "updated_count": updated_count,
            "skipped_count": skipped_count,
            "error_count": error_count,
            "dry_run": dry_run,
            "category_name": category.name,
            "category_id": category_id,
            "errors": errors[:10],
        }

    @classmethod
    def import_from_file(
        cls,
        session: Session,
        file_path: Path,
        limit: Optional[int] = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Read a normalized hotel JSON file and import into the database."""
        if not file_path.exists():
            raise FileNotFoundError(f"Normalized hotel file not found: {file_path}")

        with open(file_path, "r", encoding="utf-8") as f:
            records = json.load(f)

        if not isinstance(records, list):
            raise ValueError(f"Expected JSON array in {file_path}, got {type(records)}")

        return cls.import_normalized_hotels(
            session=session,
            records=records,
            limit=limit,
            dry_run=dry_run,
        )

    @classmethod
    def verify_database_data(cls, session: Session) -> dict[str, Any]:
        """Query database to verify hotel counts, details links, OSM identifiers, and sample records."""
        cls.ensure_schema(session)

        category = cls.get_hotel_category(session)
        category_id = category.id

        # Total places in this category
        all_places = list(session.exec(
            select(Place).where(Place.category_id == category_id)
        ).all())

        total_places = len(all_places)
        with_osm_ids = sum(1 for p in all_places if p.osm_type and p.osm_id)
        with_coords = sum(1 for p in all_places if p.latitude is not None and p.longitude is not None)
        with_details = 0
        with_images = 0

        sample_records: list[dict[str, Any]] = []

        for p in all_places:
            detail = session.get(HotelDetail, p.id)
            if detail:
                with_details += 1
            imgs = list(session.exec(select(PlaceImage).where(PlaceImage.place_id == p.id)).all())
            if imgs:
                with_images += 1

            if len(sample_records) < 5:
                sample_records.append({
                    "id": p.id,
                    "name": p.name,
                    "osm_type": p.osm_type,
                    "osm_id": p.osm_id,
                    "latitude": p.latitude,
                    "longitude": p.longitude,
                    "star_rating": detail.star_rating if detail else None,
                    "amenities": detail.amenities if detail else None,
                    "phone": detail.phone if detail else None,
                    "website": detail.website if detail else None,
                    "email": detail.email if detail else None,
                    "rooms": detail.rooms if detail else None,
                    "beds": detail.beds if detail else None,
                    "has_image": len(imgs) > 0,
                })

        return {
            "category_id": category_id,
            "category_name": category.name,
            "total_places": total_places,
            "with_osm_ids": with_osm_ids,
            "with_coords": with_coords,
            "with_details": with_details,
            "with_images": with_images,
            "samples": sample_records,
        }

