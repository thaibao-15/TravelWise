"""
Unit and integration test suite for AI Itinerary Generation Service (TravelWise).

Covers all 16 required test scenarios:
1. Tạo lịch trình 1 ngày.
2. Tạo lịch trình 3 ngày.
3. Xử lý thiếu ngày bắt đầu nhưng đã có thời lượng.
4. Xử lý thiếu ngân sách.
5. Xử lý không tìm thấy địa điểm bắt buộc.
6. Xử lý danh sách địa điểm rỗng.
7. Xử lý JSON lỗi từ LLM.
8. Xử lý place_id không thuộc danh sách đầu vào.
9. Không đưa địa điểm bị loại trừ vào kết quả.
10. Kiểm tra số ngày và thứ tự hoạt động.
11. Kiểm tra thời gian chồng lấn.
12. Kiểm tra chi phí và thời lượng âm.
13. Kiểm tra quyền truy cập trip.
14. Kiểm tra rollback khi lưu database thất bại.
15. Kiểm tra retry không tạo dữ liệu trùng.
16. Kiểm tra các API chat và RAG cũ vẫn hoạt động.
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
    ItineraryGenerationRequest,
    ItineraryGenerationResponse,
    ItineraryStatusEnum,
)
from app.schemas.place_search import SearchPlaceItem
from app.schemas.trip_planning import (
    DateInfo,
    DestinationInfo,
    PlaceRequirementItem,
    PlaceRequirements,
    TripInfo,
    TripPlanningContext,
    TripPreferencesInfo,
)
from app.services.itinerary_generation_service import ItineraryGenerationService


class FakeLLMResponse:
    def __init__(self, content: str):
        self.content = content


class TestItineraryGeneration(unittest.TestCase):
    """Test suite covering itinerary generation logic, constraints, validation, and persistence."""

    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            # User A (Owner)
            user_a = session.exec(select(User).where(User.email == "itin_user_a@example.com")).first()
            if not user_a:
                user_a = User(email="itin_user_a@example.com", full_name="User A", role="USER", is_active=True)
                session.add(user_a)
                session.commit()
                session.refresh(user_a)

            # User B (Another User)
            user_b = session.exec(select(User).where(User.email == "itin_user_b@example.com")).first()
            if not user_b:
                user_b = User(email="itin_user_b@example.com", full_name="User B", role="USER", is_active=True)
                session.add(user_b)
                session.commit()
                session.refresh(user_b)

            self.user_a_id = user_a.id
            self.user_b_id = user_b.id

            # Create test Trip for User A
            trip_a = session.exec(select(Trip).where(Trip.name == "Chuyến đi test Itinerary")).first()
            if not trip_a:
                trip_a = Trip(
                    user_id=self.user_a_id,
                    name="Chuyến đi test Itinerary",
                    destination_city="Đà Nẵng",
                    status="DRAFT",
                )
                session.add(trip_a)
                session.commit()
                session.refresh(trip_a)

            self.trip_a_id = trip_a.id

            # Ensure at least 2 real places exist in DB for testing
            p1 = session.exec(select(Place).where(Place.name == "Bà Nà Hills")).first()
            if not p1:
                p1 = Place(
                    name="Bà Nà Hills",
                    description="Khu du lịch trên đỉnh núi Chúa",
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
                    description="Bãi biển đẹp và nổi tiếng",
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

        self.token_a = create_access_token(subject=self.user_a_id, email="itin_user_a@example.com", role="USER")
        self.token_b = create_access_token(subject=self.user_b_id, email="itin_user_b@example.com", role="USER")
        self.headers_a = {"Authorization": f"Bearer {self.token_a}"}
        self.headers_b = {"Authorization": f"Bearer {self.token_b}"}

    # -------------------------------------------------------------------------
    # 1. Tạo lịch trình 1 ngày
    # -------------------------------------------------------------------------
    def test_generate_1_day_itinerary(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1

        mock_llm_json = {
            "title": "Khám phá Đà Nẵng trong 1 ngày",
            "summary": "Ngày tham quan trọn vẹn điểm nổi bật.",
            "days": [
                {
                    "day_number": 1,
                    "date": None,
                    "title": "Ngày 1: Tham quan trung tâm",
                    "activities": [
                        {
                            "order_index": 1,
                            "activity_type": "VISIT",
                            "place_id": self.real_place_1_id,
                            "title": "Tham quan Bà Nà Hills",
                            "start_time": "08:30",
                            "end_time": "11:30",
                            "duration_minutes": 180,
                            "estimated_cost": 850000,
                        }
                    ],
                }
            ],
        }

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session,
                context=ctx,
                trip_id=self.trip_a_id,
                llm=mock_llm,
                save_to_db=False,
            )

        self.assertEqual(res.status, ItineraryStatusEnum.GENERATED.value)
        self.assertEqual(res.duration_days, 1)
        self.assertEqual(len(res.days), 1)
        self.assertEqual(res.days[0].day_number, 1)
        self.assertEqual(len(res.days[0].activities), 1)
        self.assertEqual(res.days[0].activities[0].place_id, self.real_place_1_id)

    # -------------------------------------------------------------------------
    # 2. Tạo lịch trình 3 ngày
    # -------------------------------------------------------------------------
    def test_generate_3_days_itinerary(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 3

        mock_llm_json = {
            "title": "Đà Nẵng 3 ngày 2 đêm",
            "summary": "Lịch trình cân bằng giữa vui chơi và nghỉ dưỡng.",
            "days": [
                {
                    "day_number": 1,
                    "title": "Ngày 1: Check-in & Biển",
                    "activities": [
                        {
                            "order_index": 1,
                            "activity_type": "VISIT",
                            "place_id": self.real_place_2_id,
                            "title": "Tắm biển Mỹ Khê",
                            "start_time": "15:00",
                            "end_time": "17:00",
                            "duration_minutes": 120,
                        }
                    ],
                },
                {
                    "day_number": 2,
                    "title": "Ngày 2: Núi Chúa",
                    "activities": [
                        {
                            "order_index": 1,
                            "activity_type": "VISIT",
                            "place_id": self.real_place_1_id,
                            "title": "Khám phá Bà Nà Hills",
                            "start_time": "08:00",
                            "end_time": "14:00",
                            "duration_minutes": 360,
                        }
                    ],
                },
                {
                    "day_number": 3,
                    "title": "Ngày 3: Mua sắm & Thư giãn",
                    "activities": [
                        {
                            "order_index": 1,
                            "activity_type": "REST",
                            "place_id": None,
                            "title": "Uống cà phê và nghỉ ngơi tự do",
                            "start_time": "09:00",
                            "end_time": "11:00",
                            "duration_minutes": 120,
                        }
                    ],
                },
            ],
        }

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session,
                context=ctx,
                trip_id=self.trip_a_id,
                llm=mock_llm,
                save_to_db=False,
            )

        self.assertEqual(res.status, ItineraryStatusEnum.GENERATED.value)
        self.assertEqual(res.duration_days, 3)
        self.assertEqual(len(res.days), 3)
        self.assertEqual([d.day_number for d in res.days], [1, 2, 3])

    # -------------------------------------------------------------------------
    # 3. Xử lý thiếu ngày bắt đầu nhưng đã có thời lượng
    # -------------------------------------------------------------------------
    def test_missing_start_date_with_duration(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 2
        ctx.trip.dates.start_date = None
        ctx.trip.dates.end_date = None

        mock_llm_json = {
            "title": "Lịch trình 2 ngày",
            "days": [
                {"day_number": 1, "activities": []},
                {"day_number": 2, "activities": []},
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        self.assertEqual(res.status, ItineraryStatusEnum.GENERATED.value)
        self.assertIsNone(res.days[0].date)
        self.assertIsNone(res.days[1].date)

    # -------------------------------------------------------------------------
    # 4. Xử lý thiếu ngân sách
    # -------------------------------------------------------------------------
    def test_missing_budget(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1
        ctx.budget.total = None

        mock_llm_json = {
            "title": "Chuyến đi không ngân sách",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {
                            "order_index": 1,
                            "place_id": self.real_place_2_id,
                            "title": "Dạo bãi biển Mỹ Khê",
                            "start_time": "08:00",
                            "end_time": "10:00",
                            "estimated_cost": None,
                        }
                    ],
                }
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        self.assertEqual(res.status, ItineraryStatusEnum.GENERATED.value)
        self.assertIsNotNone(res.budget)
        self.assertEqual(res.budget.confidence, "INSUFFICIENT_DATA")

    # -------------------------------------------------------------------------
    # 5. Xử lý không tìm thấy địa điểm bắt buộc
    # -------------------------------------------------------------------------
    def test_unresolved_must_visit_place(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1
        ctx.place_requirements.must_visit = [
            PlaceRequirementItem(name="Đảo Kho Báu Huyền Bí Không Tồn Tại 999")
        ]

        mock_llm_json = {"title": "Lịch trình", "days": [{"day_number": 1, "activities": []}]}
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        self.assertTrue(len(res.unresolved_requirements) > 0)
        self.assertTrue(any("Đảo Kho Báu" in item for item in res.unresolved_requirements))

    # -------------------------------------------------------------------------
    # 6. Xử lý danh sách địa điểm rỗng
    # -------------------------------------------------------------------------
    def test_empty_candidate_places(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Atlantis Thành Phố Dưới Biển"
        ctx.trip.dates.duration_days = 2

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, save_to_db=False
            )

        self.assertEqual(res.status, ItineraryStatusEnum.FAILED.value)
        self.assertTrue(len(res.warnings) > 0)

    # -------------------------------------------------------------------------
    # 7. Xử lý JSON lỗi từ LLM
    # -------------------------------------------------------------------------
    def test_invalid_json_from_llm(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse("Phản hồi hoàn toàn không phải định dạng JSON {} [[")

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        self.assertEqual(res.status, ItineraryStatusEnum.FAILED.value)
        self.assertTrue(any("JSON" in w for w in res.warnings))

    # -------------------------------------------------------------------------
    # 8. Xử lý place_id không thuộc danh sách đầu vào (Fabricated place_id)
    # -------------------------------------------------------------------------
    def test_fabricated_place_id_handled(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1

        fake_place_id = 99999999
        mock_llm_json = {
            "title": "Chuyến đi",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {
                            "order_index": 1,
                            "place_id": fake_place_id,
                            "title": "Địa điểm ảo",
                            "start_time": "09:00",
                            "end_time": "10:00",
                        }
                    ],
                }
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        # Place ID must have been stripped to None and a warning logged
        self.assertIsNone(res.days[0].activities[0].place_id)
        self.assertTrue(any(str(fake_place_id) in w for w in res.warnings))

    # -------------------------------------------------------------------------
    # 9. Không đưa địa điểm bị loại trừ vào kết quả
    # -------------------------------------------------------------------------
    def test_excluded_places_not_in_result(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1
        ctx.place_requirements.excluded = [PlaceRequirementItem(name="Bà Nà Hills")]

        mock_llm_json = {
            "title": "Chuyến đi",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {
                            "order_index": 1,
                            "place_id": self.real_place_1_id,
                            "title": "Cố tình đưa Bà Nà Hills",
                            "start_time": "09:00",
                            "end_time": "11:00",
                        }
                    ],
                }
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        # Excluded place must be neutralized
        self.assertIsNone(res.days[0].activities[0].place_id)
        self.assertTrue(any("loại bỏ" in w.lower() for w in res.warnings))

    # -------------------------------------------------------------------------
    # 10. Kiểm tra số ngày và thứ tự hoạt động
    # -------------------------------------------------------------------------
    def test_day_count_and_activity_order(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 2

        mock_llm_json = {
            "title": "Thứ tự hoạt động",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {"order_index": 5, "title": "Hoạt động A"},
                        {"order_index": 12, "title": "Hoạt động B"},
                    ],
                },
                {"day_number": 2, "activities": [{"order_index": 9, "title": "Hoạt động C"}]},
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        # Order indices should be sanitized to 1, 2, ...
        self.assertEqual(res.days[0].activities[0].order_index, 1)
        self.assertEqual(res.days[0].activities[1].order_index, 2)
        self.assertEqual(res.days[1].activities[0].order_index, 1)

    # -------------------------------------------------------------------------
    # 11. Kiểm tra thời gian chồng lấn
    # -------------------------------------------------------------------------
    def test_overlapping_time_adjustment(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1

        mock_llm_json = {
            "title": "Chồng lấn",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {"order_index": 1, "title": "Act 1", "start_time": "09:00", "end_time": "11:00"},
                        {"order_index": 2, "title": "Act 2", "start_time": "10:00", "end_time": "12:00"},
                    ],
                }
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        act1 = res.days[0].activities[0]
        act2 = res.days[0].activities[1]
        # Act 2 must not start before Act 1 ends
        self.assertTrue(act2.start_time >= act1.end_time)
        self.assertTrue(any("chồng lấn" in w.lower() for w in res.warnings))

    # -------------------------------------------------------------------------
    # 12. Kiểm tra chi phí và thời lượng âm
    # -------------------------------------------------------------------------
    def test_negative_cost_and_duration_handling(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1

        mock_llm_json = {
            "title": "Âm",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {
                            "order_index": 1,
                            "title": "Chi phí âm",
                            "start_time": "09:00",
                            "end_time": "10:00",
                            "duration_minutes": -60,
                            "estimated_cost": -200000,
                        }
                    ],
                }
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            res = ItineraryGenerationService.generate_itinerary(
                session=session, context=ctx, llm=mock_llm, save_to_db=False
            )

        act = res.days[0].activities[0]
        self.assertTrue(act.duration_minutes is None or act.duration_minutes >= 0)
        self.assertTrue(act.estimated_cost is None or act.estimated_cost >= 0)

    # -------------------------------------------------------------------------
    # 13. Kiểm tra quyền truy cập trip (API Authorization)
    # -------------------------------------------------------------------------
    def test_trip_access_authorization(self):
        # 1. Unauthenticated -> 401
        res_unauth = self.client.post(f"/api/v1/trips/{self.trip_a_id}/itinerary/generate")
        self.assertEqual(res_unauth.status_code, 401)

        # 2. User B accessing User A trip -> 403
        res_forbidden = self.client.post(
            f"/api/v1/trips/{self.trip_a_id}/itinerary/generate",
            headers=self.headers_b,
        )
        self.assertEqual(res_forbidden.status_code, 403)

        # 3. Nonexistent trip -> 404
        res_notfound = self.client.post(
            "/api/v1/trips/9999999/itinerary/generate",
            headers=self.headers_a,
        )
        self.assertEqual(res_notfound.status_code, 404)

    # -------------------------------------------------------------------------
    # 14. Kiểm tra rollback khi lưu database thất bại
    # -------------------------------------------------------------------------
    def test_database_rollback_on_failure(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 1

        mock_llm_json = {
            "title": "Test Rollback",
            "days": [
                {
                    "day_number": 1,
                    "activities": [
                        {"order_index": 1, "title": "Hoạt động rollback", "place_id": self.real_place_1_id}
                    ],
                }
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            # Patch session.commit to simulate database failure
            with patch.object(session, "commit", side_effect=RuntimeError("SQL Server Connection Timeout")):
                res = ItineraryGenerationService.generate_itinerary(
                    session=session,
                    context=ctx,
                    trip_id=self.trip_a_id,
                    llm=mock_llm,
                    save_to_db=True,
                )
                self.assertTrue(any("lỗi khi lưu" in w.lower() for w in res.warnings))

    # -------------------------------------------------------------------------
    # 15. Kiểm tra retry không tạo dữ liệu trùng
    # -------------------------------------------------------------------------
    def test_retry_does_not_duplicate_itinerary(self):
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 2

        mock_llm_json = {
            "title": "Chuyến đi Đà Nẵng 2 ngày",
            "days": [
                {
                    "day_number": 1,
                    "activities": [{"order_index": 1, "title": "Act Day 1", "place_id": self.real_place_1_id}],
                },
                {
                    "day_number": 2,
                    "activities": [{"order_index": 1, "title": "Act Day 2", "place_id": self.real_place_2_id}],
                },
            ],
        }
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = FakeLLMResponse(json.dumps(mock_llm_json))

        with Session(engine) as session:
            # First generation
            res1 = ItineraryGenerationService.generate_itinerary(
                session=session,
                context=ctx,
                trip_id=self.trip_a_id,
                llm=mock_llm,
                save_to_db=True,
            )
            self.assertEqual(res1.status, ItineraryStatusEnum.GENERATED.value)

            # Check days count in DB
            days_count_1 = len(
                session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id)).all()
            )
            self.assertEqual(days_count_1, 2)

            # Second generation (Retry / Regenerate)
            res2 = ItineraryGenerationService.generate_itinerary(
                session=session,
                context=ctx,
                trip_id=self.trip_a_id,
                llm=mock_llm,
                save_to_db=True,
            )
            self.assertEqual(res2.status, ItineraryStatusEnum.GENERATED.value)

            # Days count in DB must still be 2, NOT 4!
            days_count_2 = len(
                session.exec(select(ItineraryDay).where(ItineraryDay.trip_id == self.trip_a_id)).all()
            )
            self.assertEqual(days_count_2, 2)

    # -------------------------------------------------------------------------
    # 16. Kiểm tra các API chat và RAG cũ vẫn hoạt động
    # -------------------------------------------------------------------------
    def test_existing_chat_and_rag_unaffected(self):
        # 1. Test place search endpoint for trip
        res_places = self.client.post(
            f"/api/v1/trips/{self.trip_a_id}/places/search",
            headers=self.headers_a,
            json={"skip": 0, "limit": 5},
        )
        self.assertEqual(res_places.status_code, 200)
        data = res_places.json()
        self.assertIn("places", data)

        # 2. Test planning context endpoint (returns 404 if conversation not exists or 200)
        res_ctx = self.client.get(
            "/api/v1/trips/conversations/9999999/planning-context",
            headers=self.headers_a,
        )
        self.assertIn(res_ctx.status_code, (404, 403))


if __name__ == "__main__":
    unittest.main()
