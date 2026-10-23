import asyncio
from datetime import time
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi import HTTPException
import httpx

from app.schemas.osm_restaurant import NormalizedRestaurant, OSMBoundingBox, OpeningHourSlot
from app.services.osm_restaurant_service import OSMRestaurantService


class TestOSMRestaurantService(unittest.TestCase):
    def test_build_overpass_query(self) -> None:
        bbox = OSMBoundingBox(south=15.95, west=108.15, north=16.15, east=108.30)
        query = OSMRestaurantService.build_overpass_query(bbox, timeout_seconds=25)

        self.assertIn("[out:json][timeout:25];", query)
        self.assertIn('node["amenity"="restaurant"](15.95,108.15,16.15,108.3);', query)
        self.assertIn('way["amenity"="restaurant"](15.95,108.15,16.15,108.3);', query)
        self.assertIn('relation["amenity"="restaurant"](15.95,108.15,16.15,108.3);', query)
        self.assertIn("out body center;", query)

    def test_bounding_box_validation(self) -> None:
        with self.assertRaises(ValueError):
            OSMBoundingBox(south=16.5, north=16.0, west=108.0, east=108.5)

        with self.assertRaises(ValueError):
            OSMBoundingBox(south=15.0, north=16.0, west=109.0, east=108.0)

        with self.assertRaises(ValueError):
            OSMBoundingBox(south=-100.0, north=16.0, west=108.0, east=108.5)

    def test_normalize_node_element(self) -> None:
        raw_node = {
            "type": "node",
            "id": 1001,
            "lat": 16.0678,
            "lon": 108.2234,
            "tags": {
                "amenity": "restaurant",
                "name": "Nhà Hàng Cơm Niêu Đà Nẵng",
                "addr:housenumber": "123",
                "addr:street": "Nguyễn Tri Phương",
                "addr:suburb": "Chính Gián",
                "addr:district": "Thanh Khê",
                "addr:city": "Đà Nẵng",
                "cuisine": "vietnamese;seafood",
                "opening_hours": "Mo-Su 09:00-22:00",
                "diet:vegetarian": "yes",
                "phone": "+84 236 3888999",
                "website": "https://comnieudanang.vn",
                "image": "https://example.com/images/comnieu.jpg",
            },
        }

        normalized = OSMRestaurantService.normalize_element(raw_node)

        self.assertEqual(normalized.osm_id, 1001)
        self.assertEqual(normalized.osm_type, "node")
        self.assertEqual(normalized.name, "Nhà Hàng Cơm Niêu Đà Nẵng")
        self.assertEqual(normalized.latitude, 16.0678)
        self.assertEqual(normalized.longitude, 108.2234)
        self.assertEqual(
            normalized.address,
            "123 Nguyễn Tri Phương, Chính Gián, Thanh Khê, Đà Nẵng",
        )
        self.assertEqual(normalized.street, "Nguyễn Tri Phương")
        self.assertEqual(normalized.housenumber, "123")
        self.assertEqual(normalized.quarter, "Chính Gián")
        self.assertEqual(normalized.district, "Thanh Khê")
        self.assertEqual(normalized.city, "Đà Nẵng")
        self.assertEqual(normalized.cuisine, "vietnamese;seafood")
        self.assertEqual(normalized.opening_hours_raw, "Mo-Su 09:00-22:00")
        self.assertTrue(normalized.is_vegetarian)
        self.assertEqual(normalized.phone, "+84 236 3888999")
        self.assertEqual(normalized.website, "https://comnieudanang.vn")
        self.assertEqual(normalized.image_url, "https://example.com/images/comnieu.jpg")
        self.assertIsNone(normalized.wikimedia_commons)

        # Verify parsed opening hours slots
        self.assertEqual(len(normalized.opening_hours), 7)
        self.assertEqual(normalized.opening_hours[0].day_of_week, 0)
        self.assertEqual(normalized.opening_hours[0].open_time, time(9, 0))
        self.assertEqual(normalized.opening_hours[0].close_time, time(22, 0))

    def test_normalize_way_element_with_center(self) -> None:
        raw_way = {
            "type": "way",
            "id": 2002,
            "center": {
                "lat": 16.0712,
                "lon": 108.2345,
            },
            "tags": {
                "amenity": "restaurant",
                "name:vi": "Bếp Cuốn Đà Nẵng",
                "addr:full": "54 Nguyễn Văn Thoại, Bắc Mỹ Phú, Ngũ Hành Sơn, Đà Nẵng",
                "cuisine": "vietnamese",
                "diet:vegetarian": "no",
                "wikimedia_commons": "File:Bep_Cuon_Da_Nang_2025.jpg",
            },
        }

        normalized = OSMRestaurantService.normalize_element(raw_way)

        self.assertEqual(normalized.osm_id, 2002)
        self.assertEqual(normalized.osm_type, "way")
        self.assertEqual(normalized.name, "Bếp Cuốn Đà Nẵng")
        self.assertEqual(normalized.latitude, 16.0712)
        self.assertEqual(normalized.longitude, 108.2345)
        self.assertEqual(
            normalized.address,
            "54 Nguyễn Văn Thoại, Bắc Mỹ Phú, Ngũ Hành Sơn, Đà Nẵng",
        )
        self.assertEqual(normalized.cuisine, "vietnamese")
        self.assertFalse(normalized.is_vegetarian)
        self.assertEqual(normalized.wikimedia_commons, "File:Bep_Cuon_Da_Nang_2025.jpg")
        self.assertEqual(
            normalized.image_url,
            "https://commons.wikimedia.org/wiki/Special:FilePath/Bep_Cuon_Da_Nang_2025.jpg",
        )

    def test_normalize_relation_element_with_split_opening_hours(self) -> None:
        raw_relation = {
            "type": "relation",
            "id": 3003,
            "center": {
                "lat": 16.0456,
                "lon": 108.2178,
            },
            "tags": {
                "amenity": "restaurant",
                "name": "Madame Lân Restaurant",
                "opening_hours": "Mo-Fr 07:00-21:00; Sa-Su 08:00-22:00",
                "image": "File:Madame_Lan_Restaurant.png",
            },
        }

        normalized = OSMRestaurantService.normalize_element(raw_relation)

        self.assertEqual(normalized.osm_id, 3003)
        self.assertEqual(normalized.osm_type, "relation")
        self.assertEqual(normalized.name, "Madame Lân Restaurant")
        self.assertEqual(normalized.latitude, 16.0456)
        self.assertEqual(normalized.longitude, 108.2178)
        self.assertEqual(normalized.wikimedia_commons, "File:Madame_Lan_Restaurant.png")
        self.assertEqual(
            normalized.image_url,
            "https://commons.wikimedia.org/wiki/Special:FilePath/Madame_Lan_Restaurant.png",
        )

        # 5 days (Mo-Fr) + 2 days (Sa-Su) = 7 slots
        self.assertEqual(len(normalized.opening_hours), 7)
        # Monday
        self.assertEqual(normalized.opening_hours[0].day_of_week, 0)
        self.assertEqual(normalized.opening_hours[0].open_time, time(7, 0))
        self.assertEqual(normalized.opening_hours[0].close_time, time(21, 0))
        # Saturday
        self.assertEqual(normalized.opening_hours[5].day_of_week, 5)
        self.assertEqual(normalized.opening_hours[5].open_time, time(8, 0))
        self.assertEqual(normalized.opening_hours[5].close_time, time(22, 0))

    def test_normalize_way_missing_center(self) -> None:
        raw_way = {
            "type": "way",
            "id": 4004,
            "tags": {
                "amenity": "restaurant",
                "name": "Quán Cơm Ven Đường",
            },
        }

        normalized = OSMRestaurantService.normalize_element(raw_way)

        self.assertEqual(normalized.osm_id, 4004)
        self.assertEqual(normalized.name, "Quán Cơm Ven Đường")
        self.assertIsNone(normalized.latitude)
        self.assertIsNone(normalized.longitude)

    def test_normalize_missing_sparse_data_strict_nulls(self) -> None:
        sparse_node = {
            "type": "node",
            "id": 5005,
            "lat": 16.0500,
            "lon": 108.2000,
            "tags": {
                "amenity": "restaurant",
            },
        }

        normalized = OSMRestaurantService.normalize_element(sparse_node)

        self.assertEqual(normalized.osm_id, 5005)
        self.assertIsNone(normalized.name)
        self.assertIsNone(normalized.address)
        self.assertIsNone(normalized.street)
        self.assertIsNone(normalized.housenumber)
        self.assertIsNone(normalized.quarter)
        self.assertIsNone(normalized.district)
        self.assertIsNone(normalized.city)
        self.assertIsNone(normalized.cuisine)
        self.assertIsNone(normalized.opening_hours_raw)
        self.assertEqual(normalized.opening_hours, [])
        self.assertIsNone(normalized.is_vegetarian)
        self.assertIsNone(normalized.image_url)
        self.assertIsNone(normalized.wikimedia_commons)
        self.assertIsNone(normalized.phone)
        self.assertIsNone(normalized.website)

    def test_opening_hours_24_7(self) -> None:
        slots = OSMRestaurantService.parse_opening_hours("24/7")
        self.assertEqual(len(slots), 7)
        for idx, slot in enumerate(slots):
            self.assertEqual(slot.day_of_week, idx)
            self.assertEqual(slot.open_time, time(0, 0))
            self.assertEqual(slot.close_time, time(23, 59))

    def test_opening_hours_unparseable_fails_gracefully(self) -> None:
        slots = OSMRestaurantService.parse_opening_hours("sunrise to sunset, PH closed")
        self.assertEqual(slots, [])

    def test_filter_unnamed_and_missing_coords(self) -> None:
        elements = [
            {"type": "node", "id": 1, "lat": 16.0, "lon": 108.0, "tags": {"name": "A"}},
            {"type": "node", "id": 2, "lat": 16.0, "lon": 108.0, "tags": {}},
            {"type": "way", "id": 3, "tags": {"name": "B"}},
        ]

        # Normalization with filters
        res = OSMRestaurantService.normalize_elements(
            elements,
            skip_unnamed=True,
            skip_missing_coords=True,
        )
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0].osm_id, 1)


class TestOSMOverpassHttp(unittest.IsolatedAsyncioTestCase):
    async def test_fetch_raw_elements_success(self) -> None:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "version": 0.6,
            "generator": "Overpass API",
            "elements": [
                {
                    "type": "node",
                    "id": 9999,
                    "lat": 16.06,
                    "lon": 108.22,
                    "tags": {"name": "Hải Sản Bé Mặn"},
                }
            ],
        }
        mock_response.raise_for_status.return_value = None

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response

        bbox = OSMBoundingBox(south=15.9, west=108.0, north=16.2, east=108.3)
        elements = await OSMRestaurantService.fetch_raw_elements(
            bbox=bbox,
            client=mock_client,
            max_retries=1,
        )

        self.assertEqual(len(elements), 1)
        self.assertEqual(elements[0]["id"], 9999)
        mock_client.post.assert_awaited_once()

    async def test_fetch_raw_elements_retries_on_429(self) -> None:
        # First call returns 429, second returns 200
        resp_429 = MagicMock()
        resp_429.status_code = 429

        resp_200 = MagicMock()
        resp_200.status_code = 200
        resp_200.json.return_value = {"elements": [{"id": 101, "type": "node"}]}
        resp_200.raise_for_status.return_value = None

        mock_client = AsyncMock()
        mock_client.post.side_effect = [resp_429, resp_200]

        with patch("asyncio.sleep", new_callable=AsyncMock) as mock_sleep:
            elements = await OSMRestaurantService.fetch_raw_elements(
                client=mock_client,
                max_retries=2,
            )

        self.assertEqual(len(elements), 1)
        self.assertEqual(mock_client.post.await_count, 2)
        mock_sleep.assert_awaited_once()

    async def test_fetch_raw_elements_invalid_json(self) -> None:
        bad_resp = MagicMock()
        bad_resp.status_code = 200
        bad_resp.json.side_effect = ValueError("Invalid JSON")
        bad_resp.raise_for_status.return_value = None

        mock_client = AsyncMock()
        mock_client.post.return_value = bad_resp

        with self.assertRaises(HTTPException) as cm:
            await OSMRestaurantService.fetch_raw_elements(
                client=mock_client,
                max_retries=0,
            )

        self.assertEqual(cm.exception.status_code, 502)


if __name__ == "__main__":
    unittest.main()
