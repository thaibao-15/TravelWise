import json
import logging
from pathlib import Path
from typing import Any, Optional

from sqlalchemy import inspect, text
from sqlmodel import Session, select

from app.models.category import Category
from app.models.opening_hours import OpeningHours
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.models.restaurant_detail import RestaurantDetail
from app.schemas.osm_restaurant import NormalizedRestaurant

logger = logging.getLogger(__name__)


class OSMImporterService:
    """Service to import normalized OpenStreetMap restaurant records into SQL Server."""

    @staticmethod
    def ensure_schema(session: Session) -> None:
        """Ensure source, osm_type, osm_id columns and filtered unique index exist in places table."""
        bind = session.get_bind()
        insp = inspect(bind)
        cols = [c["name"] for c in insp.get_columns("places")]

        if "source" not in cols or "osm_type" not in cols or "osm_id" not in cols:
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

    @staticmethod
    def get_restaurant_category(session: Session) -> Category:
        """Find existing restaurant/food category to prevent duplicate category creation.

        Prioritizes existing categories named 'Ẩm thực', 'Nhà hàng', etc.
        Uses Unicode-safe matching across SQL Server, PostgreSQL, and SQLite.
        """
        all_categories = list(session.exec(select(Category)).all())
        for c in all_categories:
            if not c.name:
                continue
            name_lower = c.name.strip().lower()
            if any(kw in name_lower for kw in ("ẩm thực", "nhà hàng", "restaurant", "quán ăn", "food")):
                return c

        # Fallback only if no food category exists in the system
        new_cat = Category(
            name="Ẩm thực",
            description="Nhà hàng, quán ăn, đặc sản địa phương",
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
    def import_single_restaurant(
        cls,
        session: Session,
        item: dict[str, Any],
        category_id: int,
    ) -> str:
        """Import or update a single normalized restaurant record.

        Returns:
            "added" if a new place was inserted.
            "updated" if an existing place was updated.
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
        cuisine = item.get("cuisine")
        is_veg = item.get("is_vegetarian")
        image_url = item.get("image_url")
        opening_hours = item.get("opening_hours") or []

        # 1. Deduplication lookup strictly by (osm_type, osm_id)
        # Never merge distinct places just because names are similar!
        existing_place = session.exec(
            select(Place).where(
                Place.osm_type == osm_type,
                Place.osm_id == osm_id,
            )
        ).first()

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

            # Insert RestaurantDetail
            if cuisine or is_veg is not None:
                detail = RestaurantDetail(
                    place_id=place.id,
                    cuisine_type=cuisine[:100] if cuisine else None,
                    is_vegetarian=is_veg,
                )
                session.add(detail)

            # Insert PlaceImage
            if image_url:
                img = PlaceImage(
                    place_id=place.id,
                    url=image_url,
                    is_primary=True,
                    description=f"Ảnh từ OpenStreetMap cho {name}",
                )
                session.add(img)

            # Insert OpeningHours slots
            for slot in opening_hours:
                d = slot.get("day_of_week")
                ot = slot.get("open_time")
                ct = slot.get("close_time")
                if d is not None and ot and ct:
                    # Parse time if string
                    from datetime import time as dt_time
                    if isinstance(ot, str):
                        parts = list(map(int, ot.split(":")))
                        ot = dt_time(parts[0], parts[1], parts[2] if len(parts) > 2 else 0)
                    if isinstance(ct, str):
                        parts = list(map(int, ct.split(":")))
                        ct = dt_time(parts[0], parts[1], parts[2] if len(parts) > 2 else 0)

                    session.add(
                        OpeningHours(
                            place_id=place.id,
                            day_of_week=d,
                            open_time=ot,
                            close_time=ct,
                        )
                    )

            return "added"

        else:
            # ─── UPDATE EXISTING PLACE (Preserve manual input & is_deleted) ───
            # Rule 8: Do not overwrite manual information with null or empty from OSM
            # Rule 9: Do not alter is_deleted flag
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

            # Update RestaurantDetail
            detail = session.get(RestaurantDetail, existing_place.id)
            if detail:
                if cuisine and str(cuisine).strip():
                    detail.cuisine_type = str(cuisine).strip()[:100]
                if is_veg is not None:
                    detail.is_vegetarian = is_veg
                # Notice: detail.price_range is untouched to preserve manual inputs
                session.add(detail)
            elif cuisine or is_veg is not None:
                detail = RestaurantDetail(
                    place_id=existing_place.id,
                    cuisine_type=cuisine[:100] if cuisine else None,
                    is_vegetarian=is_veg,
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
    def import_normalized_records(
        cls,
        session: Session,
        records: list[dict[str, Any]],
        limit: Optional[int] = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Import a list of normalized restaurant records with transaction safety and detailed metrics."""
        # Ensure source, osm_type, osm_id columns and filtered unique index exist
        cls.ensure_schema(session)

        category = cls.get_restaurant_category(session)
        category_id = category.id

        if limit is not None and limit > 0:
            records = records[:limit]

        added_count = 0
        updated_count = 0
        skipped_count = 0
        error_count = 0
        errors: list[str] = []

        logger.info(
            "Starting OSM restaurant import: %d records, Category '%s' (id=%s), dry_run=%s",
            len(records),
            category.name,
            category_id,
            dry_run,
        )

        for idx, item in enumerate(records, 1):
            try:
                # Use sub-transactions (savepoints) so one record failure does not abort the batch
                with session.begin_nested():
                    res = cls.import_single_restaurant(session, item, category_id)
                    if res == "added":
                        added_count += 1
                    elif res == "updated":
                        updated_count += 1
                    else:
                        skipped_count += 1
            except Exception as exc:
                error_count += 1
                err_msg = f"Error importing OSM item {item.get('osm_type')}/{item.get('osm_id')}: {exc}"
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
    def import_from_normalized_file(
        cls,
        session: Session,
        file_path: Path,
        limit: Optional[int] = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Import all normalized records from JSON file with transaction safety and detailed metrics."""
        if not file_path.exists():
            raise FileNotFoundError(f"Normalized data file not found: {file_path}")

        with open(file_path, "r", encoding="utf-8") as f:
            records: list[dict[str, Any]] = json.load(f)

        if not isinstance(records, list):
            raise ValueError(f"Expected list of records in {file_path}, got {type(records)}")

        return cls.import_normalized_records(
            session=session,
            records=records,
            limit=limit,
            dry_run=dry_run,
        )
