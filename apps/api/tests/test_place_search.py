"""
Unit and integration test suite for Place Search Service (TravelWise AI Itinerary).

Covers all 14 scenarios specified in Task Requirements:
1. Search places by city.
2. Filter by category (include & avoid).
3. Prioritize must-visit places.
4. Filter out excluded places.
5. Handle interests with no match gracefully.
6. Handle unresolved must-visit places.
7. Handle missing price and opening hours without fabrication.
8. Handle context without destination.
9. Handle multiple destinations (additional_destinations).
10. Pagination and limits (skip & limit).
11. Trip access authorization (401, 403, 404, 200).
12. No valid records matching criteria.
13. Database session dependency integrity.
14. Real database records verification.
"""

import json
import unittest

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.core.security import create_access_token
from app.db.session import engine
from app.main import app
from app.models.category import Category
from app.models.place import Place
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.models.user import User
from app.schemas.place_search import PlaceSearchRequest, PlaceSearchResponse
from app.schemas.trip_planning import (
    DestinationInfo,
    PlaceRequirementItem,
    PlaceRequirements,
    TripInfo,
    TripPlanningContext,
    TripPreferencesInfo,
)
from app.services.place_search_service import PlaceSearchService


class TestPlaceSearchService(unittest.TestCase):
    """Test suite for PlaceSearchService and related API endpoints."""

    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            # User A
            user_a = session.exec(select(User).where(User.email == "search_user_a@example.com")).first()
            if not user_a:
                user_a = User(email="search_user_a@example.com", full_name="User A", role="USER", is_active=True)
                session.add(user_a)
                session.commit()
                session.refresh(user_a)

            # User B
            user_b = session.exec(select(User).where(User.email == "search_user_b@example.com")).first()
            if not user_b:
                user_b = User(email="search_user_b@example.com", full_name="User B", role="USER", is_active=True)
                session.add(user_b)
                session.commit()
                session.refresh(user_b)

            self.user_a_id = user_a.id
            self.user_b_id = user_b.id

            # Create sample trip with context for User A
            trip_a = session.exec(select(Trip).where(Trip.user_id == self.user_a_id)).first()
            if not trip_a:
                trip_a = Trip(
                    user_id=self.user_a_id,
                    name="Chuyến đi Đà Nẵng",
                    destination_city="Đà Nẵng",
                    status="DRAFT",
                )
                session.add(trip_a)
                session.commit()
                session.refresh(trip_a)

            self.trip_a_id = trip_a.id

            # Attach context snapshot to trip_preferences
            ctx_a = TripPlanningContext()
            ctx_a.trip.trip_id = self.trip_a_id
            ctx_a.trip.destination.city = "Đà Nẵng"
            ctx_a.preferences.interests = ["beach", "văn hóa"]
            ctx_a.place_requirements.must_visit = [PlaceRequirementItem(name="Bà Nà Hills")]

            pref_a = session.exec(select(TripPreference).where(TripPreference.trip_id == self.trip_a_id)).first()
            if not pref_a:
                pref_a = TripPreference(
                    trip_id=self.trip_a_id,
                    raw_context_snapshot=ctx_a.model_dump_json(),
                )
                session.add(pref_a)
            else:
                pref_a.raw_context_snapshot = ctx_a.model_dump_json()
                session.add(pref_a)

            # Ensure categories needed by scenarios exist
            cat_beach = session.exec(select(Category).where(Category.name == "Beach")).first()
            if not cat_beach:
                cat_beach = Category(name="Beach", description="Bãi biển")
                session.add(cat_beach)
                session.commit()
                session.refresh(cat_beach)

            cat_museum = session.exec(select(Category).where(Category.name == "Museum")).first()
            if not cat_museum:
                cat_museum = Category(name="Museum", description="Bảo tàng")
                session.add(cat_museum)
                session.commit()
                session.refresh(cat_museum)

            # Ensure places needed across scenarios 1-14 exist
            places_to_seed = [
                {
                    "name": "Bà Nà Hills",
                    "description": "Khu du lịch Bà Nà Hills",
                    "address": "Hòa Vang, Đà Nẵng",
                    "latitude": 15.998,
                    "longitude": 107.995,
                    "category_id": None,
                },
                {
                    "name": "Bãi biển Mỹ Khê",
                    "description": "Bãi biển đẹp và nổi tiếng",
                    "address": "Sơn Trà, Đà Nẵng",
                    "latitude": 16.060,
                    "longitude": 108.246,
                    "category_id": cat_beach.id,
                },
                {
                    "name": "Bảo tàng Điêu khắc Chăm Đà Nẵng",
                    "description": "Bảo tàng nghệ thuật Chăm",
                    "address": "Hải Châu, Đà Nẵng",
                    "latitude": 16.061,
                    "longitude": 108.223,
                    "category_id": cat_museum.id,
                },
                {
                    "name": "Cầu Rồng",
                    "description": "Cầu Rồng bắc qua sông Hàn",
                    "address": "Hải Châu, Đà Nẵng",
                    "latitude": 16.061,
                    "longitude": 108.227,
                    "category_id": None,
                },
                {
                    "name": "Chợ Hàn",
                    "description": "Chợ truyền thống lâu đời",
                    "address": "Hải Châu, Đà Nẵng",
                    "latitude": 16.068,
                    "longitude": 108.224,
                    "category_id": None,
                },
                {
                    "name": "Đèo Hải Vân",
                    "description": "Đèo Hải Vân hùng vĩ nối Đà Nẵng và Huế",
                    "address": "Thừa Thiên Huế",
                    "latitude": 16.191,
                    "longitude": 108.131,
                    "category_id": None,
                },
            ]

            for p_data in places_to_seed:
                p = session.exec(select(Place).where(Place.name == p_data["name"])).first()
                if not p:
                    p = Place(
                        name=p_data["name"],
                        description=p_data["description"],
                        address=p_data["address"],
                        latitude=p_data["latitude"],
                        longitude=p_data["longitude"],
                        category_id=p_data["category_id"],
                        is_deleted=False,
                    )
                    session.add(p)
                else:
                    if p_data["category_id"] and p.category_id != p_data["category_id"]:
                        p.category_id = p_data["category_id"]
                        session.add(p)

            session.commit()

        self.token_a = create_access_token(subject=self.user_a_id, email="search_user_a@example.com", role="USER")
        self.token_b = create_access_token(subject=self.user_b_id, email="search_user_b@example.com", role="USER")

        self.headers_a = {"Authorization": f"Bearer {self.token_a}"}
        self.headers_b = {"Authorization": f"Bearer {self.token_b}"}

    # -------------------------------------------------------------------------
    # Scenario 1: Tìm địa điểm theo thành phố
    # -------------------------------------------------------------------------
    def test_01_search_by_city(self):
        """Scenario 1: Find places matching destination city."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            self.assertGreater(res.total, 0)
            self.assertEqual(res.destination, "Đà Nẵng")
            for p in res.places:
                full_text = ((p.address or "") + " " + p.name).lower()
                self.assertTrue(
                    "đà nẵng" in full_text or "da nang" in full_text,
                    f"Expected 'đà nẵng' or 'da nang' in '{full_text}'"
                )

    # -------------------------------------------------------------------------
    # Scenario 2: Lọc theo category (include & avoid)
    # -------------------------------------------------------------------------
    def test_02_filter_by_category(self):
        """Scenario 2: Category filtering respects include and avoid lists."""
        with Session(engine) as session:
            # 2a. Categories to avoid: Museum (Bảo tàng)
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            ctx.place_requirements.place_categories_to_avoid = ["Museum"]

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            place_names = [p.name for p in res.places]
            self.assertNotIn("Bảo tàng Điêu khắc Chăm Đà Nẵng", place_names)

            # 2b. Categories to include: Beach
            ctx2 = TripPlanningContext()
            ctx2.trip.destination.city = "Đà Nẵng"
            ctx2.place_requirements.place_categories_to_include = ["Beach"]

            res2 = PlaceSearchService.search_places_for_itinerary(session, ctx2)
            # Top candidate should match Beach
            top_place = res2.places[0]
            self.assertTrue(
                "Beach" in (top_place.category or "")
                or "Bãi biển" in top_place.name
                or any("Beach" in r for r in top_place.match_reasons)
            )

    # -------------------------------------------------------------------------
    # Scenario 3: Ưu tiên địa điểm must_visit
    # -------------------------------------------------------------------------
    def test_03_prioritize_must_visit(self):
        """Scenario 3: Must-visit place is prioritized with highest score."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            ctx.place_requirements.must_visit = [PlaceRequirementItem(name="Bà Nà Hills", priority="HIGH")]

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            self.assertGreater(len(res.places), 0)
            first_place = res.places[0]
            self.assertEqual(first_place.name, "Bà Nà Hills")
            self.assertTrue(first_place.is_must_visit)
            self.assertGreaterEqual(first_place.score, 10.0)

    # -------------------------------------------------------------------------
    # Scenario 4: Không trả về địa điểm excluded
    # -------------------------------------------------------------------------
    def test_04_exclude_places(self):
        """Scenario 4: Hard exclusion of places in excluded list."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            ctx.place_requirements.excluded = [
                PlaceRequirementItem(name="Chợ Hàn"),
                PlaceRequirementItem(name="Cầu Rồng"),
            ]

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            place_names = [p.name for p in res.places]
            self.assertNotIn("Chợ Hàn", place_names)
            self.assertNotIn("Cầu Rồng", place_names)

    # -------------------------------------------------------------------------
    # Scenario 5: Xử lý sở thích không có kết quả phù hợp
    # -------------------------------------------------------------------------
    def test_05_interests_with_no_match(self):
        """Scenario 5: Unmatched interests do not cause error or false matches."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            ctx.preferences.interests = ["trượt tuyết sa mạc", "lặn với cá mập trắng"]

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            self.assertGreater(res.total, 0)
            for p in res.places:
                self.assertNotIn("trượt tuyết sa mạc", p.matched_interests)

    # -------------------------------------------------------------------------
    # Scenario 6: Xử lý địa điểm bắt buộc không tìm thấy
    # -------------------------------------------------------------------------
    def test_06_unresolved_must_visit(self):
        """Scenario 6: Unknown must-visit place returned in unresolved_must_visit."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            ctx.place_requirements.must_visit = [
                PlaceRequirementItem(name="Tháp Eiffel Paris"),
                PlaceRequirementItem(name="Bà Nà Hills"),
            ]

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            # Bà Nà Hills is resolved
            self.assertTrue(any(p.name == "Bà Nà Hills" for p in res.places))
            # Eiffel Tower is unresolved
            unresolved_names = [u.name for u in res.unresolved_must_visit]
            self.assertIn("Tháp Eiffel Paris", unresolved_names)
            self.assertEqual(res.unresolved_must_visit[0].reason, "Không tìm thấy trong cơ sở dữ liệu địa phương")

    # -------------------------------------------------------------------------
    # Scenario 7: Xử lý giá và giờ mở cửa bị thiếu
    # -------------------------------------------------------------------------
    def test_07_missing_price_and_opening_hours(self):
        """Scenario 7: Places without pricing or hours return None safely without fabrication."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            self.assertGreater(len(res.places), 0)
            # Find a place without opening hours / price
            place = next(p for p in res.places if p.name == "Cầu Rồng")
            self.assertIsNone(place.opening_hours)
            self.assertIsNone(place.price)

    # -------------------------------------------------------------------------
    # Scenario 8: Xử lý context chưa có điểm đến
    # -------------------------------------------------------------------------
    def test_08_context_without_destination(self):
        """Scenario 8: Context without destination searches across all places with diagnostic warning."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = None

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            self.assertGreater(res.total, 0)
            self.assertIsNone(res.destination)
            self.assertTrue(any("chưa có điểm đến" in w for w in res.warnings))

    # -------------------------------------------------------------------------
    # Scenario 9: Xử lý nhiều điểm đến (additional_destinations)
    # -------------------------------------------------------------------------
    def test_09_multiple_destinations(self):
        """Scenario 9: Search includes places in both primary and additional destinations."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            ctx.trip.destination.additional_destinations = ["Thừa Thiên Huế"]

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            place_names = [p.name for p in res.places]
            # Đèo Hải Vân is in Thừa Thiên Huế
            self.assertIn("Đèo Hải Vân", place_names)
            self.assertIn("Bà Nà Hills", place_names)

    # -------------------------------------------------------------------------
    # Scenario 10: Phân trang và giới hạn kết quả
    # -------------------------------------------------------------------------
    def test_10_pagination_and_limits(self):
        """Scenario 10: Pagination correctly slices result set."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"

            res_full = PlaceSearchService.search_places_for_itinerary(session, ctx, skip=0, limit=20)
            total = res_full.total
            self.assertGreater(total, 2)

            res_page = PlaceSearchService.search_places_for_itinerary(session, ctx, skip=1, limit=2)
            self.assertEqual(res_page.total, total)
            self.assertEqual(len(res_page.places), 2)
            self.assertEqual(res_page.places[0].place_id, res_full.places[1].place_id)

    # -------------------------------------------------------------------------
    # Scenario 11: Kiểm tra quyền truy cập trip (401, 403, 404, 200)
    # -------------------------------------------------------------------------
    def test_11_trip_access_authorization(self):
        """Scenario 11: Endpoint enforces trip access control."""
        # 11a. Non-existent trip -> 404
        resp_404 = self.client.post("/api/v1/trips/999999/places/search", headers=self.headers_a)
        self.assertEqual(resp_404.status_code, 404)

        # 11b. Unauthorized access (User B to User A's trip) -> 403
        resp_403 = self.client.post(f"/api/v1/trips/{self.trip_a_id}/places/search", headers=self.headers_b)
        self.assertEqual(resp_403.status_code, 403)

        # 11c. Unauthenticated request -> 401
        resp_401 = self.client.post(f"/api/v1/trips/{self.trip_a_id}/places/search")
        self.assertEqual(resp_401.status_code, 401)

        # 11d. Owner access -> 200 OK
        resp_200 = self.client.post(f"/api/v1/trips/{self.trip_a_id}/places/search", headers=self.headers_a)
        self.assertEqual(resp_200.status_code, 200)
        data = resp_200.json()
        self.assertEqual(data["destination"], "Đà Nẵng")
        self.assertGreater(data["total"], 0)
        self.assertEqual(data["places"][0]["name"], "Bà Nà Hills")

    # -------------------------------------------------------------------------
    # Scenario 12: Không có bản ghi hợp lệ
    # -------------------------------------------------------------------------
    def test_12_no_valid_records(self):
        """Scenario 12: Searching an unsupported destination returns empty list with 0 total."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Tokyo, Nhật Bản"

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            self.assertEqual(res.total, 0)
            self.assertEqual(len(res.places), 0)

    # -------------------------------------------------------------------------
    # Scenario 13: Đảm bảo truy vấn sử dụng database session đúng chuẩn
    # -------------------------------------------------------------------------
    def test_13_session_dependency_integrity(self):
        """Scenario 13: Verify direct endpoint /api/v1/places/search-for-itinerary executes with session dependency."""
        payload = {
            "context": {
                "trip": {
                    "destination": {"city": "Đà Nẵng"}
                },
                "preferences": {
                    "interests": ["biển"]
                }
            },
            "skip": 0,
            "limit": 5,
        }
        resp = self.client.post("/api/v1/places/search-for-itinerary", json=payload)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["destination"], "Đà Nẵng")
        self.assertGreater(len(data["places"]), 0)

    # -------------------------------------------------------------------------
    # Scenario 14: Đảm bảo không dùng dữ liệu giả để vượt qua test
    # -------------------------------------------------------------------------
    def test_14_real_database_records_verification(self):
        """Scenario 14: Place IDs returned strictly exist in SQL Server places table."""
        with Session(engine) as session:
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"

            res = PlaceSearchService.search_places_for_itinerary(session, ctx)
            db_ids = set(session.exec(select(Place.id).where(Place.is_deleted == False)).all())

            for p in res.places:
                self.assertIn(p.place_id, db_ids)
                # Confirm place actually matches in database
                db_place = session.get(Place, p.place_id)
                self.assertIsNotNone(db_place)
                self.assertEqual(db_place.name, p.name)


if __name__ == "__main__":
    unittest.main()
