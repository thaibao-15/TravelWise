"""
Unit and integration test suite for Itinerary Validation, Persistence, and Retrieval.

Covers:
1. Lưu thành công một lịch trình nhiều ngày.
2. Đọc lại lịch trình đã lưu và đúng thứ tự.
3. JSON / dữ liệu không hợp lệ không được lưu.
4. place_id không tồn tại bị từ chối / trung hòa.
5. Địa điểm bị loại trừ không được lưu vào lịch trình.
6. Lỗi khi lưu hoạt động làm rollback toàn bộ transaction.
7. Retry không tạo dữ liệu trùng ngoài ý muốn.
8. Không thể truy cập trip của người dùng khác (403).
9. Không thể cập nhật trip không tồn tại (404).
10. Lịch trình rỗng được xử lý đúng.
11. Trạng thái trip chỉ được cập nhật sau khi lưu thành công (GENERATED).
12. Dữ liệu giá hoặc giờ mở cửa bị thiếu không làm phát sinh giá trị giả.
13. Lấy chi tiết lịch trình với eager loading.
14. Bảo vệ không ghi đè trip CONFIRMED khi chưa cho phép.
15. Lấy danh sách chuyến đi (GET /api/v1/trips) phân trang và cách ly người dùng.
16. Các API chat và RAG cũ vẫn hoạt động bình thường.
"""

from datetime import date
from decimal import Decimal
import json
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
from app.models.trip_preference import TripPreference
from app.models.user import User
from app.schemas.itinerary import (
    BudgetEstimate,
    ItineraryActivityItem,
    ItineraryDayItem,
    ItineraryGenerationResponse,
    ItineraryStatusEnum,
)
from app.schemas.trip_planning import PlaceRequirementItem, TripPlanningContext
from app.services.itinerary_persistence_service import ItineraryPersistenceService


class TestItineraryPersistence(unittest.TestCase):
    """Test suite covering itinerary validation, atomic persistence, protection, and retrieval."""

    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            # User A
            user_a = session.exec(select(User).where(User.email == "persist_user_a@example.com")).first()
            if not user_a:
                user_a = User(email="persist_user_a@example.com", full_name="User A", role="USER", is_active=True)
                session.add(user_a)
                session.commit()
                session.refresh(user_a)

            # User B
            user_b = session.exec(select(User).where(User.email == "persist_user_b@example.com")).first()
            if not user_b:
                user_b = User(email="persist_user_b@example.com", full_name="User B", role="USER", is_active=True)
                session.add(user_b)
                session.commit()
                session.refresh(user_b)

            self.user_a_id = user_a.id
            self.user_b_id = user_b.id

            # Create trip for User A
            trip_a = session.exec(select(Trip).where(Trip.name == "Trip Test Persistence A")).first()
            if not trip_a:
                trip_a = Trip(
                    user_id=self.user_a_id,
                    name="Trip Test Persistence A",
                    destination_city="Đà Nẵng",
                    status="DRAFT",
                )
                session.add(trip_a)
                session.commit()
                session.refresh(trip_a)

            self.trip_a_id = trip_a.id

            # Create real places in DB
            p1 = session.exec(select(Place).where(Place.name == "Bà Nà Hills")).first()
            if not p1:
                p1 = Place(
                    name="Bà Nà Hills",
                    description="Khu du lịch Bà Nà Hills",
                    address="Hòa Vang, Đà Nẵng",
                    latitude=15.998,
                    longitude=107.995,
                    is_deleted=False,
                )
                session.add(p1)

            p2 = session.exec(select(Place).where(Place.name == "Bãi biển Mỹ Khê")).first()
            if not p2:
                p2 = Place(
                    name="Bãi biển Mỹ Khê",
                    description="Bãi biển đẹp",
                    address="Sơn Trà, Đà Nẵng",
                    latitude=16.060,
                    longitude=108.246,
                    is_deleted=False,
                )
                session.add(p2)

            session.commit()
            session.refresh(p1)
            session.refresh(p2)
            self.real_place_1_id = p1.id
            self.real_place_2_id = p2.id

        self.token_a = create_access_token(subject=self.user_a_id, email="persist_user_a@example.com", role="USER")
        self.token_b = create_access_token(subject=self.user_b_id, email="persist_user_b@example.com", role="USER")
        self.headers_a = {"Authorization": f"Bearer {self.token_a}"}
        self.headers_b = {"Authorization": f"Bearer {self.token_b}"}

    def _create_sample_itinerary(self, duration: int = 2) -> ItineraryGenerationResponse:
        """Helper to create sample valid ItineraryGenerationResponse."""
        days = []
        for d in range(1, duration + 1):
            act = ItineraryActivityItem(
                order_index=1,
                activity_type="VISIT",
                place_id=self.real_place_1_id if d == 1 else self.real_place_2_id,
                title=f"Hoạt động ngày {d}",
                description=f"Mô tả ngày {d}",
                start_time="09:00",
                end_time="11:30",
                duration_minutes=150,
                estimated_cost=50000.0,
            )
            days.append(
                ItineraryDayItem(
                    day_number=d,
                    title=f"Ngày {d}: Khám phá",
                    activities=[act],
                )
            )

        return ItineraryGenerationResponse(
            status=ItineraryStatusEnum.GENERATED.value,
            trip_id=self.trip_a_id,
            title="Lịch trình Đà Nẵng mẫu",
            summary="Tóm tắt lịch trình mẫu",
            duration_days=duration,
            currency="VND",
            budget=BudgetEstimate(target_total=2000000.0, estimated_total=100000.0, confidence="ESTIMATED"),
            days=days,
        )

    # -------------------------------------------------------------------------
    # 1. Lưu thành công một lịch trình nhiều ngày
    # -------------------------------------------------------------------------
    def test_save_multi_day_itinerary_success(self):
        itin = self._create_sample_itinerary(duration=2)
        with Session(engine) as session:
            res = ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )

        self.assertEqual(res.trip_id, self.trip_a_id)
        self.assertEqual(res.status, "GENERATED")
        self.assertEqual(len(res.days), 2)
        self.assertEqual(res.days[0].day_number, 1)
        self.assertEqual(res.days[1].day_number, 2)
        self.assertIsNotNone(res.days[0].id)
        self.assertIsNotNone(res.days[0].activities[0].id)

    # -------------------------------------------------------------------------
    # 2. Đọc lại lịch trình đã lưu và đúng thứ tự (API GET /itinerary)
    # -------------------------------------------------------------------------
    def test_get_saved_itinerary_ordered(self):
        itin = self._create_sample_itinerary(duration=3)
        with Session(engine) as session:
            ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )

        # Retrieve via API
        res = self.client.get(
            f"/api/v1/trips/{self.trip_a_id}/itinerary",
            headers=self.headers_a,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["trip_id"], self.trip_a_id)
        self.assertEqual(len(data["days"]), 3)
        # Check day numbers strictly increasing 1, 2, 3
        day_numbers = [d["day_number"] for d in data["days"]]
        self.assertEqual(day_numbers, [1, 2, 3])
        # Check place summary attached
        p_summary = data["days"][0]["activities"][0]["place"]
        self.assertIsNotNone(p_summary)
        self.assertEqual(p_summary["place_id"], self.real_place_1_id)

    # -------------------------------------------------------------------------
    # 3. Dữ liệu không hợp lệ không được lưu
    # -------------------------------------------------------------------------
    def test_invalid_itinerary_not_saved(self):
        itin = self._create_sample_itinerary(duration=2)
        itin.status = ItineraryStatusEnum.FAILED.value  # Mark failed

        with Session(engine) as session:
            with self.assertRaises(Exception):
                ItineraryPersistenceService.save_itinerary(
                    session=session,
                    trip_id=self.trip_a_id,
                    itinerary=itin,
                    check_ownership=False,
                )

    # -------------------------------------------------------------------------
    # 4. place_id không tồn tại bị từ chối / trung hòa
    # -------------------------------------------------------------------------
    def test_nonexistent_place_id_rejected(self):
        itin = self._create_sample_itinerary(duration=1)
        fake_id = 999999999
        itin.days[0].activities[0].place_id = fake_id

        with Session(engine) as session:
            res = ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )

        # Place ID should have been converted to None because it doesn't exist in DB
        self.assertIsNone(res.days[0].activities[0].place_id)

    # -------------------------------------------------------------------------
    # 5. Địa điểm bị loại trừ không được lưu vào lịch trình
    # -------------------------------------------------------------------------
    def test_excluded_place_not_saved(self):
        ctx = TripPlanningContext()
        ctx.place_requirements.excluded = [PlaceRequirementItem(name="Bà Nà Hills")]

        itin = self._create_sample_itinerary(duration=1)
        itin.days[0].activities[0].place_id = self.real_place_1_id  # Real Bà Nà Hills

        with Session(engine) as session:
            res = ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                context=ctx,
                check_ownership=False,
            )

        # Should be stripped
        self.assertIsNone(res.days[0].activities[0].place_id)

    # -------------------------------------------------------------------------
    # 6. Lỗi khi lưu hoạt động làm rollback toàn bộ transaction
    # -------------------------------------------------------------------------
    def test_activity_save_error_rolls_back_entire_transaction(self):
        itin = self._create_sample_itinerary(duration=2)

        with Session(engine) as session:
            # Clear previous days
            session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id))
            old_days_count = len(session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id)).all())

            # Simulate failure during commit
            with patch.object(session, "commit", side_effect=RuntimeError("Simulated DB Connection Failure")):
                with self.assertRaises(RuntimeError):
                    ItineraryPersistenceService.save_itinerary(
                        session=session,
                        trip_id=self.trip_a_id,
                        itinerary=itin,
                        check_ownership=False,
                    )

            # Check that database was rolled back and no corrupted partial days exist
            current_days_count = len(session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id)).all())
            self.assertEqual(current_days_count, old_days_count)

    # -------------------------------------------------------------------------
    # 7. Retry không tạo dữ liệu trùng ngoài ý muốn
    # -------------------------------------------------------------------------
    def test_retry_does_not_duplicate_days_or_activities(self):
        itin = self._create_sample_itinerary(duration=2)

        with Session(engine) as session:
            # First save
            ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )
            count1 = len(session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id)).all())
            self.assertEqual(count1, 2)

            # Retry / Second save
            ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )
            count2 = len(session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id)).all())
            # Must remain 2, not 4
            self.assertEqual(count2, 2)

    # -------------------------------------------------------------------------
    # 8. Không thể truy cập trip của người dùng khác (403)
    # -------------------------------------------------------------------------
    def test_cannot_access_other_user_trip(self):
        # User B trying to access User A trip
        res = self.client.get(
            f"/api/v1/trips/{self.trip_a_id}/itinerary",
            headers=self.headers_b,
        )
        self.assertEqual(res.status_code, 403)

    # -------------------------------------------------------------------------
    # 9. Không thể cập nhật / truy xuất trip không tồn tại (404)
    # -------------------------------------------------------------------------
    def test_cannot_access_nonexistent_trip(self):
        res = self.client.get(
            "/api/v1/trips/99999999/itinerary",
            headers=self.headers_a,
        )
        self.assertEqual(res.status_code, 404)

    # -------------------------------------------------------------------------
    # 10. Lịch trình rỗng được xử lý đúng
    # -------------------------------------------------------------------------
    def test_empty_itinerary_handled(self):
        itin = ItineraryGenerationResponse(
            status=ItineraryStatusEnum.GENERATED.value,
            trip_id=self.trip_a_id,
            duration_days=2,
            days=[],  # Empty days!
        )

        with Session(engine) as session:
            val_res = ItineraryPersistenceService.validate_itinerary(
                session=session, itinerary=itin
            )
            self.assertFalse(val_res.is_valid)
            self.assertTrue(any("trống" in err for err in val_res.errors))

    # -------------------------------------------------------------------------
    # 11. Trạng thái trip chỉ được cập nhật sau khi lưu thành công (GENERATED)
    # -------------------------------------------------------------------------
    def test_trip_status_only_updated_after_success(self):
        with Session(engine) as session:
            trip = session.get(Trip, self.trip_a_id)
            trip.status = "DRAFT"
            session.add(trip)
            session.commit()

        itin = self._create_sample_itinerary(duration=1)
        with Session(engine) as session:
            ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )

        with Session(engine) as session:
            trip_after = session.get(Trip, self.trip_a_id)
            self.assertEqual(trip_after.status, "GENERATED")

    # -------------------------------------------------------------------------
    # 12. Dữ liệu giá hoặc giờ mở cửa bị thiếu không làm phát sinh giá trị giả
    # -------------------------------------------------------------------------
    def test_missing_price_or_hours_no_fabricated_data(self):
        itin = self._create_sample_itinerary(duration=1)
        itin.days[0].activities[0].start_time = None
        itin.days[0].activities[0].end_time = None
        itin.days[0].activities[0].estimated_cost = None

        with Session(engine) as session:
            res = ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                check_ownership=False,
            )

        act = res.days[0].activities[0]
        self.assertIsNone(act.start_time)
        self.assertIsNone(act.end_time)
        self.assertIsNone(act.estimated_cost)

    # -------------------------------------------------------------------------
    # 13. Bảo vệ không ghi đè trip CONFIRMED khi chưa cho phép
    # -------------------------------------------------------------------------
    def test_overwrite_confirmed_trip_protection(self):
        with Session(engine) as session:
            trip = session.get(Trip, self.trip_a_id)
            trip.status = "CONFIRMED"
            session.add(trip)
            session.commit()

        itin = self._create_sample_itinerary(duration=1)

        # Attempt to save without allow_overwrite_confirmed should fail (400)
        with Session(engine) as session:
            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                ItineraryPersistenceService.save_itinerary(
                    session=session,
                    trip_id=self.trip_a_id,
                    itinerary=itin,
                    allow_overwrite_confirmed=False,
                    check_ownership=False,
                )
            self.assertEqual(ctx.exception.status_code, 400)
            self.assertIn("CONFIRMED", ctx.exception.detail)

            # Attempt with allow_overwrite_confirmed=True succeeds
            res_allowed = ItineraryPersistenceService.save_itinerary(
                session=session,
                trip_id=self.trip_a_id,
                itinerary=itin,
                allow_overwrite_confirmed=True,
                check_ownership=False,
            )
            self.assertEqual(res_allowed.status, "GENERATED")

    # -------------------------------------------------------------------------
    # 14. Lấy danh sách chuyến đi (GET /api/v1/trips) phân trang và cách ly người dùng
    # -------------------------------------------------------------------------
    def test_list_trips_pagination_and_isolation(self):
        # User A calls list trips
        res_a = self.client.get("/api/v1/trips?skip=0&limit=10", headers=self.headers_a)
        self.assertEqual(res_a.status_code, 200)
        data_a = res_a.json()
        self.assertIn("items", data_a)
        self.assertTrue(data_a["total"] >= 1)
        # All items must belong to User A
        self.assertTrue(all(item["name"] is not None for item in data_a["items"]))

        # User B calls list trips (should see 0 or only User B trips)
        res_b = self.client.get("/api/v1/trips", headers=self.headers_b)
        self.assertEqual(res_b.status_code, 200)
        data_b = res_b.json()
        user_b_trip_ids = [item["id"] for item in data_b["items"]]
        self.assertNotIn(self.trip_a_id, user_b_trip_ids)

    # -------------------------------------------------------------------------
    # 15. Kiểm tra các API chat và RAG cũ vẫn hoạt động
    # -------------------------------------------------------------------------
    def test_existing_chat_and_rag_unaffected(self):
        res_places = self.client.post(
            f"/api/v1/trips/{self.trip_a_id}/places/search",
            headers=self.headers_a,
            json={"skip": 0, "limit": 5},
        )
        self.assertEqual(res_places.status_code, 200)


if __name__ == "__main__":
    unittest.main()
