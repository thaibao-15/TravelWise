import json
from pathlib import Path
import tempfile
import unittest

from app.schemas.osm_hotel import NormalizedHotel
from app.services.osm_hotel_service import OSMHotelService
from scripts.normalize_osm_hotels import save_atomic_json


class TestOSMHotelNormalize(unittest.TestCase):
    def test_normalize_valid_node(self) -> None:
        raw_node = {
            "type": "node",
            "id": 1001,
            "lat": 16.065,
            "lon": 108.225,
            "tags": {
                "name": "Novotel Da Nang Premier Han River",
                "name:vi": "Khách sạn Novotel Đà Nẵng",
                "tourism": "hotel",
                "stars": "5",
                "rooms": "323",
                "beds": "400",
                "addr:housenumber": "36",
                "addr:street": "Bạch Đằng",
                "addr:district": "Hải Châu",
                "addr:city": "Đà Nẵng",
                "addr:postcode": "550000",
                "phone": "+84 236 3929999",
                "website": "https://novotel-danang-premier.com",
                "email": "H8287@accor.com",
                "opening_hours": "24/7",
                "wifi": "yes",
                "swimming_pool": "yes",
                "air_conditioning": "yes",
                "parking": "underground",
                "wheelchair": "yes",
                "image": "https://example.com/novotel.jpg",
            },
        }

        hotel, reason = OSMHotelService.normalize_element(raw_node)
        self.assertIsNone(reason)
        self.assertIsNotNone(hotel)
        assert hotel is not None

        self.assertEqual(hotel.osm_id, 1001)
        self.assertEqual(hotel.osm_type, "node")
        self.assertEqual(hotel.name, "Novotel Da Nang Premier Han River")
        self.assertEqual(hotel.latitude, 16.065)
        self.assertEqual(hotel.longitude, 108.225)
        self.assertEqual(hotel.star_rating, 5)
        self.assertEqual(hotel.rooms, 323)
        self.assertEqual(hotel.beds, 400)
        self.assertEqual(hotel.phone, "+84 236 3929999")
        self.assertEqual(hotel.website, "https://novotel-danang-premier.com")
        self.assertEqual(hotel.email, "H8287@accor.com")
        self.assertEqual(hotel.postcode, "550000")
        self.assertEqual(hotel.street, "Bạch Đằng")
        self.assertEqual(hotel.housenumber, "36")
        self.assertEqual(hotel.district, "Hải Châu")
        self.assertEqual(hotel.city, "Đà Nẵng")
        self.assertIn("36 Bạch Đằng", hotel.address or "")
        self.assertEqual(hotel.image_url, "https://example.com/novotel.jpg")
        self.assertIn("wifi", hotel.amenities)
        self.assertIn("swimming_pool", hotel.amenities)
        self.assertIn("air_conditioning", hotel.amenities)
        self.assertIn("parking", hotel.amenities)
        self.assertIn("wheelchair_accessible", hotel.amenities)

    def test_normalize_way_with_center(self) -> None:
        raw_way = {
            "type": "way",
            "id": 2002,
            "center": {"lat": 16.071, "lon": 108.231},
            "tags": {
                "name:vi": "Khách sạn Sông Hàn",
                "tourism": "hotel",
                "stars": "4",
                "addr:street": "Lê Duẩn",
                "addr:city": "Đà Nẵng",
            },
        }

        hotel, reason = OSMHotelService.normalize_element(raw_way)
        self.assertIsNone(reason)
        self.assertIsNotNone(hotel)
        assert hotel is not None

        self.assertEqual(hotel.osm_id, 2002)
        self.assertEqual(hotel.osm_type, "way")
        self.assertEqual(hotel.name, "Khách sạn Sông Hàn")
        self.assertEqual(hotel.latitude, 16.071)
        self.assertEqual(hotel.longitude, 108.231)
        self.assertEqual(hotel.star_rating, 4)

    def test_rejection_missing_name(self) -> None:
        raw = {
            "type": "node",
            "id": 3003,
            "lat": 16.05,
            "lon": 108.2,
            "tags": {"tourism": "hotel"},
        }
        hotel, reason = OSMHotelService.normalize_element(raw)
        self.assertIsNone(hotel)
        self.assertEqual(reason, "Missing name")

    def test_rejection_missing_coordinates(self) -> None:
        raw = {
            "type": "node",
            "id": 4004,
            "tags": {"name": "No Coords Hotel", "tourism": "hotel"},
        }
        hotel, reason = OSMHotelService.normalize_element(raw)
        self.assertIsNone(hotel)
        self.assertEqual(reason, "Missing coordinates")

    def test_rejection_missing_both(self) -> None:
        raw = {
            "type": "node",
            "id": 5005,
            "tags": {"tourism": "hotel"},
        }
        hotel, reason = OSMHotelService.normalize_element(raw)
        self.assertIsNone(hotel)
        self.assertEqual(reason, "Missing both name and coordinates")

    def test_star_rating_parsing(self) -> None:
        self.assertEqual(OSMHotelService.extract_star_rating({"stars": "5"}), 5)
        self.assertEqual(OSMHotelService.extract_star_rating({"stars": "4.0"}), 4)
        self.assertEqual(OSMHotelService.extract_star_rating({"stars": "3 stars"}), 3)
        self.assertIsNone(OSMHotelService.extract_star_rating({"stars": "unrated"}))
        self.assertIsNone(OSMHotelService.extract_star_rating({"stars": "10"}))
        self.assertIsNone(OSMHotelService.extract_star_rating({}))

    def test_amenities_strict_matching(self) -> None:
        # Only explicitly tagged amenities are added
        tags = {
            "internet_access": "wlan",
            "internet_access:fee": "no",
            "air_conditioning": "yes",
            "smoking": "no",
        }
        amenities = OSMHotelService.extract_amenities(tags)
        self.assertIn("wifi", amenities)
        self.assertIn("free_wifi", amenities)
        self.assertIn("air_conditioning", amenities)
        self.assertIn("non_smoking", amenities)
        self.assertNotIn("swimming_pool", amenities)
        self.assertNotIn("spa", amenities)
        self.assertNotIn("gym", amenities)

    def test_deduplication(self) -> None:
        elements = [
            {
                "type": "node",
                "id": 100,
                "lat": 16.0,
                "lon": 108.0,
                "tags": {"name": "Hotel A", "tourism": "hotel"},
            },
            {
                "type": "node",
                "id": 100,  # Duplicate
                "lat": 16.0,
                "lon": 108.0,
                "tags": {"name": "Hotel A (Duplicate)", "tourism": "hotel"},
            },
            {
                "type": "way",
                "id": 100,  # Same id, but different osm_type! Must NOT be treated as duplicate
                "center": {"lat": 16.1, "lon": 108.1},
                "tags": {"name": "Hotel B Way", "tourism": "hotel"},
            },
        ]

        valid, discarded, stats = OSMHotelService.normalize_elements(elements)
        self.assertEqual(len(valid), 2)
        self.assertEqual(stats["duplicate_count"], 1)
        self.assertEqual(valid[0]["osm_type"], "node")
        self.assertEqual(valid[0]["osm_id"], 100)
        self.assertEqual(valid[1]["osm_type"], "way")
        self.assertEqual(valid[1]["osm_id"], 100)


if __name__ == "__main__":
    unittest.main()
