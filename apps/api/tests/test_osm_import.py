import unittest
from sqlmodel import Session, SQLModel, create_engine, select

from app.models.category import Category
from app.models.opening_hours import OpeningHours
from app.models.place import Place
from app.models.place_image import PlaceImage
from app.models.restaurant_detail import RestaurantDetail
from app.services.osm_importer_service import OSMImporterService


class TestOSMImport(unittest.TestCase):
    def setUp(self) -> None:
        # Create an in-memory SQLite database for isolated, fast, and repeatable testing
        self.engine = create_engine("sqlite:///:memory:")
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)

        # Seed initial Food category
        self.category = Category(id=1, name="Ẩm thực", description="Nhà hàng, quán ăn")
        self.session.add(self.category)
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def test_reuse_existing_category(self) -> None:
        """Requirement 2: Reuse existing food/restaurant category without duplicating."""
        cat = OSMImporterService.get_restaurant_category(self.session)
        self.assertEqual(cat.id, 1)
        self.assertEqual(cat.name, "Ẩm thực")

        # Verify no second category was created
        all_cats = self.session.exec(select(Category)).all()
        self.assertEqual(len(all_cats), 1)

    def test_deduplication_running_twice_updates_without_duplicates(self) -> None:
        """Requirement 6: Running import multiple times does not create duplicate places."""
        item = {
            "osm_id": 1001,
            "osm_type": "node",
            "name": "Nhà Hàng Cơm Niêu",
            "latitude": 16.05,
            "longitude": 108.20,
            "address": "123 Nguyễn Tri Phương",
            "cuisine": "vietnamese",
            "is_vegetarian": True,
            "image_url": "https://example.com/img.jpg",
            "opening_hours": [
                {"day_of_week": 0, "open_time": "08:00:00", "close_time": "22:00:00"}
            ],
        }

        # 1st run: Added
        res1 = OSMImporterService.import_single_restaurant(
            self.session, item, self.category.id
        )
        self.session.commit()
        self.assertEqual(res1, "added")

        places_count_1 = len(self.session.exec(select(Place)).all())
        self.assertEqual(places_count_1, 1)

        # 2nd run with updated address and cuisine: Updated
        item["address"] = "125 Nguyễn Tri Phương"
        item["cuisine"] = "vietnamese;seafood"
        res2 = OSMImporterService.import_single_restaurant(
            self.session, item, self.category.id
        )
        self.session.commit()
        self.assertEqual(res2, "updated")

        # Verify place was NOT duplicated
        all_places = self.session.exec(select(Place)).all()
        self.assertEqual(len(all_places), 1)
        self.assertEqual(all_places[0].address, "125 Nguyễn Tri Phương")

        # Verify restaurant_detail updated
        detail = self.session.get(RestaurantDetail, all_places[0].id)
        self.assertIsNotNone(detail)
        self.assertEqual(detail.cuisine_type, "vietnamese;seafood")

    def test_do_not_merge_places_with_same_name(self) -> None:
        """Requirement 7: Do not merge distinct places just because they have the same name."""
        branch_1 = {
            "osm_id": 2001,
            "osm_type": "node",
            "name": "Hải Sản Bé Mặn",
            "latitude": 16.06,
            "longitude": 108.24,
            "address": "Lô 11 Võ Nguyên Giáp",
        }
        branch_2 = {
            "osm_id": 2002,
            "osm_type": "node",
            "name": "Hải Sản Bé Mặn",
            "latitude": 16.08,
            "longitude": 108.25,
            "address": "Hoàng Sa",
        }

        res1 = OSMImporterService.import_single_restaurant(
            self.session, branch_1, self.category.id
        )
        res2 = OSMImporterService.import_single_restaurant(
            self.session, branch_2, self.category.id
        )
        self.session.commit()

        self.assertEqual(res1, "added")
        self.assertEqual(res2, "added")

        all_places = self.session.exec(
            select(Place).where(Place.name == "Hải Sản Bé Mặn")
        ).all()
        self.assertEqual(len(all_places), 2)
        self.assertEqual({p.osm_id for p in all_places}, {2001, 2002})

    def test_preserve_manual_information(self) -> None:
        """Requirement 8: Do not overwrite manually entered data with null/empty from OSM."""
        # 1. Existing place originally imported or curated with manual description and price_range
        place = Place(
            name="Quán Ăn Gia Truyền",
            description="Món ăn gia truyền 3 đời, phục vụ từ năm 1975.",
            address="10 Hùng Vương",
            latitude=16.07,
            longitude=108.22,
            category_id=self.category.id,
            source="osm",
            osm_type="node",
            osm_id=3001,
            is_deleted=False,
        )
        self.session.add(place)
        self.session.flush()

        detail = RestaurantDetail(
            place_id=place.id,
            cuisine_type="vietnamese",
            price_range="30.000 - 80.000 VND",
            is_vegetarian=False,
        )
        self.session.add(detail)
        self.session.commit()

        # 2. OSM update has NO description, NO address, and NO cuisine
        sparse_update = {
            "osm_id": 3001,
            "osm_type": "node",
            "name": "Quán Ăn Gia Truyền",
            "latitude": 16.07001,
            "longitude": 108.22001,
            "address": None,
            "cuisine": None,
            "is_vegetarian": None,
        }

        res = OSMImporterService.import_single_restaurant(
            self.session, sparse_update, self.category.id
        )
        self.session.commit()
        self.assertEqual(res, "updated")

        # Verify manual description and address were NOT erased
        updated_place = self.session.get(Place, place.id)
        self.assertEqual(
            updated_place.description,
            "Món ăn gia truyền 3 đời, phục vụ từ năm 1975.",
        )
        self.assertEqual(updated_place.address, "10 Hùng Vương")
        self.assertEqual(updated_place.latitude, 16.07001)

        # Verify price_range, cuisine, and is_vegetarian were NOT erased
        updated_detail = self.session.get(RestaurantDetail, place.id)
        self.assertEqual(updated_detail.price_range, "30.000 - 80.000 VND")
        self.assertEqual(updated_detail.cuisine_type, "vietnamese")
        self.assertFalse(updated_detail.is_vegetarian)

    def test_respect_is_deleted(self) -> None:
        """Requirement 9: Respect is_deleted flag when updating."""
        deleted_place = Place(
            name="Nhà Hàng Đã Đóng Cửa",
            latitude=16.05,
            longitude=108.20,
            category_id=self.category.id,
            source="osm",
            osm_type="node",
            osm_id=4001,
            is_deleted=True,
        )
        self.session.add(deleted_place)
        self.session.commit()

        update_data = {
            "osm_id": 4001,
            "osm_type": "node",
            "name": "Nhà Hàng Đã Đóng Cửa Mới",
            "latitude": 16.051,
            "longitude": 108.201,
        }

        res = OSMImporterService.import_single_restaurant(
            self.session, update_data, self.category.id
        )
        self.session.commit()
        self.assertEqual(res, "updated")

        re_checked = self.session.get(Place, deleted_place.id)
        self.assertTrue(re_checked.is_deleted)
        self.assertEqual(re_checked.name, "Nhà Hàng Đã Đóng Cửa Mới")

    def test_handle_missing_sparse_data(self) -> None:
        """Requirement 8 & 1: Missing optional fields are handled cleanly without crashing."""
        sparse_item = {
            "osm_id": 5001,
            "osm_type": "way",
            "name": "Quán Ven Đường",
            "latitude": 16.04,
            "longitude": 108.21,
            "address": None,
            "cuisine": None,
            "is_vegetarian": None,
            "image_url": None,
            "opening_hours": [],
        }

        res = OSMImporterService.import_single_restaurant(
            self.session, sparse_item, self.category.id
        )
        self.session.commit()
        self.assertEqual(res, "added")

        place = self.session.exec(
            select(Place).where(Place.osm_id == 5001)
        ).first()
        self.assertIsNotNone(place)
        self.assertEqual(place.name, "Quán Ven Đường")
        self.assertIsNone(place.address)

        # No images and no opening hours inserted
        images = self.session.exec(
            select(PlaceImage).where(PlaceImage.place_id == place.id)
        ).all()
        hours = self.session.exec(
            select(OpeningHours).where(OpeningHours.place_id == place.id)
        ).all()
        self.assertEqual(len(images), 0)
        self.assertEqual(len(hours), 0)


if __name__ == "__main__":
    unittest.main()
