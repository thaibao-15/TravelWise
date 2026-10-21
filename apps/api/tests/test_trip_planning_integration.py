"""
Integration tests for Voice AI Trip Planning, Trip Persistence, and Itinerary Editing.

Verifies:
1. POST /api/v1/trips/save-preview saves an itinerary preview atomically.
2. Saved trip has status CONFIRMED and correct day/activity counts.
3. Idempotency: multiple submissions with the same idempotency_key do not duplicate trips or activities.
4. Ownership protection: user B cannot access or edit user A's trip.
5. Real places in SQL Server are properly linked.
"""

from datetime import date
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.core.security import create_access_token
from app.db.session import engine
from app.main import app
from app.models.category import Category
from app.models.itinerary_activity import ItineraryActivity
from app.models.itinerary_day import ItineraryDay
from app.models.place import Place
from app.models.trip import Trip
from app.models.user import User


class TestTripPlanningIntegration(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            # Setup User A
            user_a = session.exec(select(User).where(User.email == "test_planner_a@travelwise.vn")).first()
            if not user_a:
                user_a = User(
                    email="test_planner_a@travelwise.vn",
                    full_name="Planner User A",
                    hashed_password="hashed_pw_test",
                    is_active=True,
                )
                session.add(user_a)
                session.commit()
                session.refresh(user_a)
            self.user_a_id = user_a.id

            # Setup User B
            user_b = session.exec(select(User).where(User.email == "test_planner_b@travelwise.vn")).first()
            if not user_b:
                user_b = User(
                    email="test_planner_b@travelwise.vn",
                    full_name="Planner User B",
                    hashed_password="hashed_pw_test",
                    is_active=True,
                )
                session.add(user_b)
                session.commit()
                session.refresh(user_b)
            self.user_b_id = user_b.id

            # Ensure a Category and real Place exist in DB
            cat = session.exec(select(Category).where(Category.name == "Beach")).first()
            if not cat:
                cat = Category(name="Beach", description="Bãi biển")
                session.add(cat)
                session.commit()
                session.refresh(cat)

            place = session.exec(select(Place).where(Place.name == "Bãi biển Mỹ Khê Test")).first()
            if not place:
                place = Place(
                    name="Bãi biển Mỹ Khê Test",
                    description="Bãi biển đẹp tại Đà Nẵng",
                    address="Võ Nguyên Giáp, Sơn Trà, Đà Nẵng",
                    city="Đà Nẵng",
                    latitude=16.0594,
                    longitude=108.2435,
                    category_id=cat.id,
                )
                session.add(place)
                session.commit()
                session.refresh(place)
            self.test_place_id = place.id
            self.test_place_name = place.name
            self.test_place_address = place.address

        self.token_a = create_access_token(subject=self.user_a_id, email="test_planner_a@travelwise.vn", role="USER")
        self.headers_a = {"Authorization": f"Bearer {self.token_a}"}

        self.token_b = create_access_token(subject=self.user_b_id, email="test_planner_b@travelwise.vn", role="USER")
        self.headers_b = {"Authorization": f"Bearer {self.token_b}"}

    def test_save_preview_trip_success(self):
        """Test that save-preview endpoint persists an unsaved preview into SQL Server."""
        preview_data = {
            "title": "Chuyến đi Đà Nẵng 3 ngày",
            "destination": "Đà Nẵng, Việt Nam",
            "start_date": "2026-11-20",
            "end_date": "2026-11-23",
            "total_days": 2,
            "days": [
                {
                    "day_number": 1,
                    "date": "2026-11-20",
                    "theme": "Khám phá biển Đà Nẵng",
                    "activities": [
                        {
                            "activity_order": 1,
                            "place_id": self.test_place_id,
                            "title": "Tắm biển Mỹ Khê",
                            "description": "Tắm biển buổi sáng và thưởng thức nước dừa",
                            "start_time": "08:00",
                            "end_time": "10:30",
                            "activity_type": "beach",
                            "estimated_cost": 50000,
                            "place": {
                                "id": self.test_place_id,
                                "name": self.test_place_name,
                                "address": self.test_place_address,
                                "latitude": 16.0594,
                                "longitude": 108.2435,
                                "category": "Beach",
                            },
                        }
                    ],
                }
            ],
        }

        response = self.client.post(
            "/api/v1/trips/save-preview",
            json={
                "preview": preview_data,
                "idempotency_key": "test_idem_key_001",
            },
            headers=self.headers_a,
        )

        self.assertIn(response.status_code, [200, 201])
        data = response.json()
        self.assertEqual(data["status"], "CONFIRMED")
        self.assertIn("trip_id", data)
        trip_id = data["trip_id"]

        # Verify saved in DB
        with Session(engine) as session:
            saved_trip = session.get(Trip, trip_id)
            self.assertIsNotNone(saved_trip)
            self.assertEqual(saved_trip.user_id, self.user_a_id)
            self.assertEqual(saved_trip.status, "CONFIRMED")

            # Check days and activities
            days = session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == trip_id)).all()
            self.assertEqual(len(days), 1)

            activities = session.exec(
                select(ItineraryActivity).where(ItineraryActivity.itinerary_day_id == days[0].id)
            ).all()
            self.assertEqual(len(activities), 1)
            self.assertEqual(activities[0].place_id, self.test_place_id)

    def test_save_preview_idempotency(self):
        """Test that submitting the same preview with identical idempotency_key is idempotent."""
        preview_data = {
            "title": "Idempotent Trip Test",
            "destination": "Đà Nẵng",
            "start_date": "2026-12-01",
            "end_date": "2026-12-03",
            "total_days": 1,
            "days": [
                {
                    "day_number": 1,
                    "date": "2026-12-01",
                    "theme": "Day 1",
                    "activities": [
                        {
                            "activity_order": 1,
                            "place_id": self.test_place_id,
                            "title": "Điểm tham quan",
                            "start_time": "09:00",
                            "end_time": "11:00",
                        }
                    ],
                }
            ],
        }

        idem_key = "idempotent_test_key_xyz"

        # First request
        resp1 = self.client.post(
            "/api/v1/trips/save-preview",
            json={"preview": preview_data, "idempotency_key": idem_key},
            headers=self.headers_a,
        )
        self.assertIn(resp1.status_code, [200, 201])
        trip_id_1 = resp1.json()["trip_id"]

        # Second request with same key
        resp2 = self.client.post(
            "/api/v1/trips/save-preview",
            json={"preview": preview_data, "idempotency_key": idem_key},
            headers=self.headers_a,
        )
        self.assertIn(resp2.status_code, [200, 201])
        trip_id_2 = resp2.json()["trip_id"]

        # Must return the same trip_id
        self.assertEqual(trip_id_1, trip_id_2)

    def test_cross_user_isolation(self):
        """Test that user B cannot retrieve or modify user A's trip."""
        # Create a trip for user A
        with Session(engine) as session:
            trip_a = Trip(
                user_id=self.user_a_id,
                title="User A Private Trip",
                destination_city="Hà Nội",
                destination_country="Việt Nam",
                start_date=date(2026, 10, 1),
                end_date=date(2026, 10, 3),
                status="CONFIRMED",
            )
            session.add(trip_a)
            session.commit()
            session.refresh(trip_a)
            trip_a_id = trip_a.id

        # User B attempts to access trip A's itinerary
        resp_b = self.client.get(
            f"/api/v1/trips/{trip_a_id}/itinerary",
            headers=self.headers_b,
        )
        # Should be forbidden or not found
        self.assertIn(resp_b.status_code, [403, 404])

        # User B attempts to edit trip A
        resp_edit_b = self.client.post(
            f"/api/v1/trips/{trip_a_id}/itinerary/edit",
            json={"instruction": "Hacker modification"},
            headers=self.headers_b,
        )
        self.assertIn(resp_edit_b.status_code, [403, 404])


if __name__ == "__main__":
    unittest.main()
