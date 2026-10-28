import unittest
from pathlib import Path
import tempfile
import json

from scripts.normalize_osm_restaurants import (
    RejectionReason,
    evaluate_element,
    normalize_osm_data,
    save_atomic_json,
)


class TestNormalizeOSMRestaurants(unittest.TestCase):
    def test_evaluate_valid_node(self) -> None:
        element = {
            "type": "node",
            "id": 101,
            "lat": 16.05,
            "lon": 108.20,
            "tags": {
                "name": "Nhà Hàng Cơm Niêu",
                "cuisine": "vietnamese",
                "addr:street": "Nguyễn Tri Phương",
                "addr:city": "Đà Nẵng",
            },
        }
        normalized, reason = evaluate_element(element)
        self.assertIsNone(reason)
        self.assertIsNotNone(normalized)
        self.assertEqual(normalized.osm_id, 101)
        self.assertEqual(normalized.name, "Nhà Hàng Cơm Niêu")
        self.assertEqual(normalized.latitude, 16.05)
        self.assertEqual(normalized.longitude, 108.20)
        self.assertEqual(normalized.address, "Nguyễn Tri Phương, Đà Nẵng")
        self.assertEqual(normalized.cuisine, "vietnamese")
        # Missing values must remain None (no hallucinations)
        self.assertIsNone(normalized.phone)
        self.assertIsNone(normalized.website)
        self.assertIsNone(normalized.image_url)

    def test_evaluate_valid_way_with_center(self) -> None:
        element = {
            "type": "way",
            "id": 202,
            "center": {"lat": 16.06, "lon": 108.22},
            "tags": {
                "name": "Bếp Cuốn",
                "cuisine": "vietnamese",
            },
        }
        normalized, reason = evaluate_element(element)
        self.assertIsNone(reason)
        self.assertIsNotNone(normalized)
        self.assertEqual(normalized.osm_id, 202)
        self.assertEqual(normalized.osm_type, "way")
        self.assertEqual(normalized.latitude, 16.06)
        self.assertEqual(normalized.longitude, 108.22)

    def test_rejection_missing_name(self) -> None:
        element = {
            "type": "node",
            "id": 303,
            "lat": 16.07,
            "lon": 108.23,
            "tags": {"amenity": "restaurant", "cuisine": "seafood"},
        }
        normalized, reason = evaluate_element(element)
        self.assertIsNone(normalized)
        self.assertEqual(reason, RejectionReason.MISSING_NAME)

    def test_rejection_missing_coordinates(self) -> None:
        # Way without center coordinates
        element = {
            "type": "way",
            "id": 404,
            "tags": {"name": "Quán Cơm Không Tọa Độ"},
        }
        normalized, reason = evaluate_element(element)
        self.assertIsNone(normalized)
        self.assertEqual(reason, RejectionReason.MISSING_COORDINATES)

    def test_rejection_missing_both(self) -> None:
        element = {
            "type": "way",
            "id": 505,
            "tags": {"amenity": "restaurant"},
        }
        normalized, reason = evaluate_element(element)
        self.assertIsNone(normalized)
        self.assertEqual(reason, RejectionReason.MISSING_BOTH)

    def test_do_not_merge_same_name_different_id(self) -> None:
        # 2 branches of the same restaurant brand
        raw_fixture = {
            "elements": [
                {
                    "type": "node",
                    "id": 1001,
                    "lat": 16.05,
                    "lon": 108.20,
                    "tags": {"name": "Hải Sản Bé Mặn", "addr:street": "Võ Nguyên Giáp"},
                },
                {
                    "type": "node",
                    "id": 1002,
                    "lat": 16.07,
                    "lon": 108.22,
                    "tags": {"name": "Hải Sản Bé Mặn", "addr:street": "Hoàng Sa"},
                },
            ]
        }
        valid_records, discarded_records, stats = normalize_osm_data(raw_fixture)
        self.assertEqual(len(valid_records), 2)
        self.assertEqual(stats["valid_count"], 2)
        self.assertEqual(stats["discarded_count"], 0)
        self.assertEqual(valid_records[0]["osm_id"], 1001)
        self.assertEqual(valid_records[1]["osm_id"], 1002)
        # Streets are distinct
        self.assertIn("Võ Nguyên Giáp", valid_records[0]["address"])
        self.assertIn("Hoàng Sa", valid_records[1]["address"])

    def test_stats_and_attribute_counting(self) -> None:
        raw_fixture = {
            "elements": [
                {
                    "type": "node",
                    "id": 1,
                    "lat": 16.0,
                    "lon": 108.0,
                    "tags": {
                        "name": "Restaurant A",
                        "cuisine": "vietnamese",
                        "addr:street": "Street 1",
                        "opening_hours": "08:00-22:00",
                        "image": "https://example.com/img.jpg",
                        "diet:vegetarian": "yes",
                    },
                },
                {
                    "type": "node",
                    "id": 2,
                    "lat": 16.1,
                    "lon": 108.1,
                    "tags": {
                        "name": "Restaurant B",
                    },
                },
                {
                    "type": "node",
                    "id": 3,
                    "lat": 16.2,
                    "lon": 108.2,
                    "tags": {},  # Missing name
                },
            ]
        }
        valid_records, discarded_records, stats = normalize_osm_data(raw_fixture)
        self.assertEqual(stats["total_input"], 3)
        self.assertEqual(stats["valid_count"], 2)
        self.assertEqual(stats["discarded_count"], 1)
        self.assertEqual(stats["attributes"]["with_cuisine"], 1)
        self.assertEqual(stats["attributes"]["with_address"], 1)
        self.assertEqual(stats["attributes"]["with_opening_hours"], 1)
        self.assertEqual(stats["attributes"]["with_image_url"], 1)
        self.assertEqual(stats["attributes"]["with_vegetarian"], 1)

    def test_save_atomic_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "output.json"
            data = [{"id": 1, "name": "Test"}]
            save_atomic_json(data, out_file)
            self.assertTrue(out_file.exists())
            with open(out_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            self.assertEqual(loaded, data)


if __name__ == "__main__":
    unittest.main()
