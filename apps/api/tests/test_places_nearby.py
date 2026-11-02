import unittest
from datetime import datetime, timezone
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient

from app.api.deps import get_session
from app.main import app, fastapi_app
from app.models.place import Place
from app.services.place_service import PlaceService


class TestNearbyPlaces(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.original_get_session = fastapi_app.dependency_overrides.get(get_session)
        fastapi_app.dependency_overrides[get_session] = lambda: None

    def tearDown(self):
        if self.original_get_session is None:
            fastapi_app.dependency_overrides.pop(get_session, None)
        else:
            fastapi_app.dependency_overrides[get_session] = self.original_get_session

    def test_nearby_endpoint_returns_distance_and_validates_coordinates(self):
        place = Place(
            id=42,
            name="Cầu Rồng",
            latitude=16.061,
            longitude=108.227,
            is_deleted=False,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
        )
        with patch(
            "app.api.routes.places.PlaceService.get_nearby_places",
            return_value=[(place, 1.234)],
        ):
            response = self.client.get(
                "/api/v1/places/nearby?latitude=16.06&longitude=108.22"
            )
            invalid_response = self.client.get(
                "/api/v1/places/nearby?latitude=91&longitude=108.22"
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["id"], 42)
        self.assertEqual(response.json()[0]["distance_km"], 1.23)
        self.assertEqual(invalid_response.status_code, 422)

    def test_service_filters_by_radius_and_sorts_by_distance_across_dateline(self):
        close_place = Place(
            id=1,
            name="Gần qua kinh tuyến",
            latitude=0,
            longitude=-179.99,
            is_deleted=False,
        )
        farther_place = Place(
            id=2,
            name="Xa hơn",
            latitude=0,
            longitude=179.9,
            is_deleted=False,
        )
        outside_radius = Place(
            id=3,
            name="Ngoài bán kính",
            latitude=0,
            longitude=179.7,
            is_deleted=False,
        )
        session = Mock()
        session.exec.return_value.all.return_value = [
            farther_place,
            outside_radius,
            close_place,
        ]

        results = PlaceService.get_nearby_places(
            session,
            latitude=0,
            longitude=179.99,
            radius_km=11,
        )

        self.assertEqual([place.id for place, _ in results], [1, 2])
        self.assertLess(results[0][1], results[1][1])


if __name__ == "__main__":
    unittest.main()
