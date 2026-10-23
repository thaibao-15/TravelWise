import unittest
from sqlmodel import Session, SQLModel, create_engine, select

from app.models.category import Category
from app.models.hotel_detail import HotelDetail
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.services.osm_hotel_importer_service import OSMHotelImporterService


from sqlalchemy import event
from sqlalchemy.pool import StaticPool


class TestOSMHotelImport(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)

        # Seed initial Hotel category
        self.category = Category(
            id=7,
            name="Lưu trú và nghỉ dưỡng",
            description="Khách sạn, resort, homestay và căn hộ du lịch.",
        )
        self.session.add(self.category)
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def test_reuse_existing_hotel_category(self) -> None:
        """Requirement: Reuse existing accommodation category without duplicating."""
        cat = OSMHotelImporterService.get_hotel_category(self.session)
        self.assertEqual(cat.id, 7)
        self.assertEqual(cat.name, "Lưu trú và nghỉ dưỡng")

        # Verify no duplicate category was created
        all_cats = list(self.session.exec(select(Category)).all())
        self.assertEqual(len(all_cats), 1)

    def test_import_single_hotel_new_and_update(self) -> None:
        """Test inserting a new hotel and updating it without duplication."""
        item = {
            "osm_id": 9901,
            "osm_type": "node",
            "name": "Novotel Han River",
            "latitude": 16.08,
            "longitude": 108.22,
            "address": "36 Bạch Đằng",
            "star_rating": 5,
            "amenities": ["wifi", "swimming_pool", "air_conditioning"],
            "image_url": "https://example.com/novotel.jpg",
            "phone": "+84 236 3929 999",
            "website": "https://novotel-danang.com",
            "email": "H8287@accor.com",
            "rooms": 323,
            "beds": 450,
        }

        # 1. First run: Insert
        res1 = OSMHotelImporterService.import_single_hotel(
            self.session, item, self.category.id
        )
        self.session.commit()
        self.assertEqual(res1, "added")

        # Verify Place
        place = self.session.exec(
            select(Place).where(Place.osm_type == "node", Place.osm_id == 9901)
        ).first()
        self.assertIsNotNone(place)
        assert place is not None
        self.assertEqual(place.name, "Novotel Han River")
        self.assertEqual(place.category_id, 7)
        self.assertEqual(place.source, "osm")

        # Verify HotelDetail
        detail = self.session.get(HotelDetail, place.id)
        self.assertIsNotNone(detail)
        assert detail is not None
        self.assertEqual(detail.star_rating, 5)
        self.assertIn("wifi", detail.amenities or "")
        self.assertIn("swimming_pool", detail.amenities or "")
        self.assertEqual(detail.phone, "+84 236 3929 999")
        self.assertEqual(detail.website, "https://novotel-danang.com")
        self.assertEqual(detail.email, "H8287@accor.com")
        self.assertEqual(detail.rooms, 323)
        self.assertEqual(detail.beds, 450)
        self.assertIsNone(detail.price_per_night)  # Pricing never invented

        # Verify PlaceImage
        images = list(self.session.exec(select(PlaceImage).where(PlaceImage.place_id == place.id)).all())
        self.assertEqual(len(images), 1)
        self.assertEqual(images[0].url, "https://example.com/novotel.jpg")

        # 2. Second run: Update existing hotel
        updated_item = {
            "osm_id": 9901,
            "osm_type": "node",
            "name": "Novotel Da Nang Premier Han River",
            "latitude": 16.081,
            "longitude": 108.221,
            "address": "36 Bạch Đằng, Hải Châu",
            "star_rating": 5,
            "amenities": ["wifi", "swimming_pool", "spa"],
            "image_url": "https://example.com/novotel.jpg",
        }

        # Set manual price on detail to verify it is NOT overwritten
        detail.price_per_night = 2500000.0
        self.session.add(detail)
        self.session.commit()

        res2 = OSMHotelImporterService.import_single_hotel(
            self.session, updated_item, self.category.id
        )
        self.session.commit()
        self.assertEqual(res2, "updated")

        # Verify update results
        all_places = list(self.session.exec(select(Place).where(Place.osm_type == "node", Place.osm_id == 9901)).all())
        self.assertEqual(len(all_places), 1)  # No duplicate place!
        self.assertEqual(all_places[0].name, "Novotel Da Nang Premier Han River")
        self.assertEqual(all_places[0].address, "36 Bạch Đằng, Hải Châu")

        # Verify manual pricing was preserved
        detail_after = self.session.get(HotelDetail, place.id)
        assert detail_after is not None
        self.assertEqual(float(detail_after.price_per_night or 0), 2500000.0)

    def test_dry_run_rollback(self) -> None:
        """Requirement: Dry-run does not write to the database (session rollback)."""
        records = [
            {
                "osm_id": 1001,
                "osm_type": "node",
                "name": "Dry Run Hotel 1",
                "latitude": 16.0,
                "longitude": 108.0,
            },
            {
                "osm_id": 1002,
                "osm_type": "way",
                "name": "Dry Run Hotel 2",
                "latitude": 16.1,
                "longitude": 108.1,
            },
        ]

        metrics = OSMHotelImporterService.import_normalized_hotels(
            session=self.session,
            records=records,
            dry_run=True,
        )

        self.assertEqual(metrics["total_records"], 2)
        self.assertEqual(metrics["added_count"], 2)
        self.assertTrue(metrics["dry_run"])

        # Verify nothing was persisted to database
        with Session(self.engine) as check_session:
            places = list(check_session.exec(select(Place)).all())
            self.assertEqual(len(places), 0)

    def test_idempotent_import_metrics(self) -> None:
        """Requirement: Re-importing same data updates records with 0 new additions."""
        records = [
            {
                "osm_id": 2001,
                "osm_type": "node",
                "name": "Hilton Da Nang",
                "latitude": 16.07,
                "longitude": 108.22,
                "star_rating": 5,
            }
        ]

        # 1st import (real commit)
        m1 = OSMHotelImporterService.import_normalized_hotels(
            session=self.session,
            records=records,
            dry_run=False,
        )
        self.assertEqual(m1["added_count"], 1)
        self.assertEqual(m1["updated_count"], 0)

        # 2nd import (real commit)
        m2 = OSMHotelImporterService.import_normalized_hotels(
            session=self.session,
            records=records,
            dry_run=False,
        )
        self.assertEqual(m2["added_count"], 0)
        self.assertEqual(m2["updated_count"], 1)

        # Still only 1 place in database
        places = list(self.session.exec(select(Place)).all())
        self.assertEqual(len(places), 1)

    def test_verify_database_data(self) -> None:
        """Test verify_database_data reports correct place counts, hotel_details links, and OSM IDs."""
        records = [
            {
                "osm_id": 5001,
                "osm_type": "node",
                "name": "Furama Resort Danang",
                "latitude": 16.04,
                "longitude": 108.24,
                "star_rating": 5,
                "amenities": ["swimming_pool", "spa", "wifi"],
                "image_url": "https://example.com/furama.jpg",
            }
        ]
        OSMHotelImporterService.import_normalized_hotels(
            session=self.session,
            records=records,
            dry_run=False,
        )

        db_info = OSMHotelImporterService.verify_database_data(self.session)
        self.assertEqual(db_info["total_places"], 1)
        self.assertEqual(db_info["with_osm_ids"], 1)
        self.assertEqual(db_info["with_coords"], 1)
        self.assertEqual(db_info["with_details"], 1)
        self.assertEqual(db_info["with_images"], 1)
        self.assertEqual(len(db_info["samples"]), 1)
        self.assertEqual(db_info["samples"][0]["name"], "Furama Resort Danang")
        self.assertEqual(db_info["samples"][0]["star_rating"], 5)


if __name__ == "__main__":
    unittest.main()
