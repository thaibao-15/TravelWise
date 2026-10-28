import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import httpx

from app.schemas.osm_restaurant import OSMBoundingBox
from app.services.osm_hotel_service import OSMHotelService
from scripts.fetch_osm_hotels import (
    build_overpass_query,
    extract_coordinates,
    fetch_raw_osm_hotels,
    save_atomic_json,
    verify_and_report,
)


class TestOSMHotelFetch(unittest.TestCase):
    def test_build_overpass_query_service(self) -> None:
        bbox = OSMBoundingBox(south=15.9, west=107.8, north=16.3, east=108.4)
        query = OSMHotelService.build_overpass_query(bbox, timeout_seconds=45)

        self.assertIn("[out:json][timeout:45];", query)
        self.assertIn('node["tourism"="hotel"](15.9,107.8,16.3,108.4);', query)
        self.assertIn('way["tourism"="hotel"](15.9,107.8,16.3,108.4);', query)
        self.assertIn('relation["tourism"="hotel"](15.9,107.8,16.3,108.4);', query)
        self.assertIn("out body center;", query)

    def test_build_overpass_query_script(self) -> None:
        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        query = build_overpass_query(bbox, timeout_seconds=60)

        self.assertIn("[out:json][timeout:60];", query)
        self.assertIn('node["tourism"="hotel"](15.9,107.8,16.3,108.4);', query)
        self.assertIn('way["tourism"="hotel"](15.9,107.8,16.3,108.4);', query)
        self.assertIn('relation["tourism"="hotel"](15.9,107.8,16.3,108.4);', query)
        self.assertIn("out body center;", query)

    def test_extract_coordinates_node(self) -> None:
        node = {"type": "node", "id": 1, "lat": 16.05, "lon": 108.2}
        lat, lon = extract_coordinates(node)
        self.assertEqual(lat, 16.05)
        self.assertEqual(lon, 108.2)

        service_lat, service_lon = OSMHotelService.extract_coordinates(node)
        self.assertEqual(service_lat, 16.05)
        self.assertEqual(service_lon, 108.2)

    def test_extract_coordinates_way_center(self) -> None:
        way = {
            "type": "way",
            "id": 200,
            "center": {"lat": 16.12, "lon": 108.25},
        }
        lat, lon = extract_coordinates(way)
        self.assertEqual(lat, 16.12)
        self.assertEqual(lon, 108.25)

        service_lat, service_lon = OSMHotelService.extract_coordinates(way)
        self.assertEqual(service_lat, 16.12)
        self.assertEqual(service_lon, 108.25)

    def test_extract_coordinates_relation_center(self) -> None:
        rel = {
            "type": "relation",
            "id": 300,
            "center": {"lat": 16.08, "lon": 108.22},
        }
        lat, lon = extract_coordinates(rel)
        self.assertEqual(lat, 16.08)
        self.assertEqual(lon, 108.22)

    def test_extract_coordinates_invalid_or_missing(self) -> None:
        self.assertEqual(extract_coordinates({}), (None, None))
        self.assertEqual(extract_coordinates({"lat": "bad", "lon": "val"}), (None, None))
        self.assertEqual(
            OSMHotelService.extract_coordinates({"lat": 150.0, "lon": 108.0}),
            (None, None),
        )

    def test_extract_name(self) -> None:
        self.assertEqual(
            OSMHotelService.extract_name({"name:vi": "Khách sạn Mường Thanh", "name": "Muong Thanh Hotel"}),
            "Muong Thanh Hotel",
        )
        self.assertEqual(
            OSMHotelService.extract_name({"name:vi": "Khách sạn Biển Đông"}),
            "Khách sạn Biển Đông",
        )
        self.assertIsNone(OSMHotelService.extract_name({}))

    @patch("httpx.Client.post")
    def test_fetch_raw_osm_hotels_success(self, mock_post: MagicMock) -> None:
        fake_payload = {
            "version": 0.6,
            "generator": "Overpass API",
            "elements": [
                {
                    "type": "node",
                    "id": 1001,
                    "lat": 16.06,
                    "lon": 108.21,
                    "tags": {"name": "Grand Tourane Hotel", "tourism": "hotel", "stars": "5"},
                },
                {
                    "type": "way",
                    "id": 2002,
                    "center": {"lat": 16.07, "lon": 108.23},
                    "tags": {"name": "Hilton Da Nang", "tourism": "hotel", "stars": "5"},
                },
            ],
        }
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = fake_payload
        mock_post.return_value = mock_response

        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        result = fetch_raw_osm_hotels(bbox=bbox, timeout_seconds=10, max_retries=1)

        self.assertIn("elements", result)
        self.assertEqual(len(result["elements"]), 2)
        self.assertEqual(result["elements"][0]["tags"]["name"], "Grand Tourane Hotel")

    @patch("httpx.Client.post")
    def test_fetch_raw_osm_hotels_retry_on_429(self, mock_post: MagicMock) -> None:
        resp_429 = MagicMock()
        resp_429.status_code = 429

        resp_200 = MagicMock()
        resp_200.status_code = 200
        resp_200.json.return_value = {"elements": [{"type": "node", "id": 1, "tags": {"tourism": "hotel"}}]}

        mock_post.side_effect = [resp_429, resp_200]

        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        with patch("time.sleep") as mock_sleep:
            result = fetch_raw_osm_hotels(bbox=bbox, timeout_seconds=10, max_retries=2, initial_backoff=0.01)

        self.assertEqual(mock_post.call_count, 2)
        self.assertEqual(len(result["elements"]), 1)
        mock_sleep.assert_called_once()

    def test_save_atomic_json_and_verify_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "test_hotels.json"
            sample_data = {
                "elements": [
                    {
                        "type": "node",
                        "id": 101,
                        "lat": 16.05,
                        "lon": 108.2,
                        "tags": {"name": "Novotel Da Nang", "tourism": "hotel", "stars": "5"},
                    },
                    {
                        "type": "way",
                        "id": 102,
                        "center": {"lat": 16.06, "lon": 108.22},
                        "tags": {"name": "Vinpearl Resort", "tourism": "hotel", "stars": "5"},
                    },
                    {
                        "type": "relation",
                        "id": 103,
                        "center": {"lat": 16.07, "lon": 108.24},
                        "tags": {"name": "InterContinental", "tourism": "hotel"},
                    },
                    {
                        "type": "node",
                        "id": 104,
                        "lat": 16.08,
                        "lon": 108.25,
                        "tags": {"tourism": "hotel"},  # unnamed
                    },
                ]
            }

            save_atomic_json(sample_data, out_file)
            self.assertTrue(out_file.exists())

            # Read back
            with open(out_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            self.assertEqual(len(loaded["elements"]), 4)

            # Test verify_and_report
            success = verify_and_report(out_file)
            self.assertTrue(success)


if __name__ == "__main__":
    unittest.main()
