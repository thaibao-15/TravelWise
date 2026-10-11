"""
Comprehensive test suite for Conversation-Based Trip Planning Context Extraction.

Covers all 13 required scenarios from Task specification:
1. Full extraction from a single message.
2. Information synthesis across multiple chat turns.
3. Updating budget, dates, or destination.
4. Removing a place from must-visit list.
5. Missing dates or budget (evaluating missing_information & readiness).
6. Conversation containing only general tourism questions (intent=False).
7. Invalid schema, illegal enums, or bad data types.
8. LLM returning null for fields with existing valid data (safe merge).
9. Conflicting information between turns.
10. Conversation does not exist or unauthorized user access.
11. Request retry does not duplicate trips.
12. Extraction failure does not break chat.
13. Database transaction failure rollback consistency.
"""

from datetime import datetime
from decimal import Decimal
import json
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.core.security import create_access_token
from app.db.base import _utcnow
from app.db.session import engine
from app.main import app
from app.models.ai_context import AIContext
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.trip import Trip
from app.models.trip_preference import TripPreference
from app.models.user import User
from app.schemas.trip_planning import (
    BudgetFlexibilityEnum,
    BudgetInfo,
    BudgetScopeEnum,
    DateFlexibilityEnum,
    DateInfo,
    DestinationFlexibilityEnum,
    DestinationInfo,
    ExtractionMetadata,
    GroupTypeEnum,
    MissingInfoImportanceEnum,
    PlaceRequirementItem,
    PlaceRequirements,
    PlanningState,
    ScheduleConstraints,
    SchedulePaceEnum,
    SpecialRequirements,
    TravelersInfo,
    TripInfo,
    TripPlanningContext,
    TripPreferencesInfo,
    TripStatusEnum,
)
from app.services.conversation_service import ConversationService
from app.services.trip_planning_service import TripPlanningContextExtractionService


class TestTripPlanningContextExtraction(unittest.TestCase):
    """Test suite covering TripPlanningContext schema, service, merging, and API endpoints."""

    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            # User A
            user_a = session.exec(select(User).where(User.email == "trip_user_a@example.com")).first()
            if not user_a:
                user_a = User(email="trip_user_a@example.com", full_name="User A", role="USER", is_active=True)
                session.add(user_a)
                session.commit()
                session.refresh(user_a)

            # User B
            user_b = session.exec(select(User).where(User.email == "trip_user_b@example.com")).first()
            if not user_b:
                user_b = User(email="trip_user_b@example.com", full_name="User B", role="USER", is_active=True)
                session.add(user_b)
                session.commit()
                session.refresh(user_b)

            self.user_a_id = user_a.id
            self.user_b_id = user_b.id

            # Clean up prior test trips for these users
            old_trips = session.exec(select(Trip).where(Trip.user_id.in_([self.user_a_id, self.user_b_id]))).all()
            for t in old_trips:
                session.delete(t)
            session.commit()

        self.token_a = create_access_token(subject=self.user_a_id, email="trip_user_a@example.com", role="USER")
        self.token_b = create_access_token(subject=self.user_b_id, email="trip_user_b@example.com", role="USER")

        self.headers_a = {"Authorization": f"Bearer {self.token_a}"}
        self.headers_b = {"Authorization": f"Bearer {self.token_b}"}

    # -------------------------------------------------------------------------
    # Scenario 1: Trích xuất đầy đủ từ một tin nhắn
    # -------------------------------------------------------------------------
    def test_scenario_01_full_extraction_from_single_message(self):
        """Scenario 1: Extract all parameters from a single rich user message."""
        mock_raw = {
            "schema_version": "1.0",
            "trip": {
                "trip_id": None,
                "conversation_id": None,
                "name": "Chuyến đi Đà Nẵng",
                "destination": {
                    "city": "Đà Nẵng",
                    "country": "Việt Nam",
                    "additional_destinations": ["Hội An"],
                    "destination_flexibility": "FIXED",
                },
                "dates": {
                    "start_date": "2026-11-15",
                    "end_date": "2026-11-17",
                    "duration_days": 3,
                    "nights": 2,
                    "date_flexibility": "EXACT",
                },
                "travelers": {
                    "adults": 2,
                    "children": 0,
                    "group_type": "COUPLE",
                    "special_traveler_needs": [],
                },
                "purpose": ["Nghỉ dưỡng"],
                "status": "DRAFT",
            },
            "budget": {
                "total": 5000000,
                "currency": "VND",
                "scope": "TOTAL",
                "allocation": {"transport": 1000000, "accommodation": 2000000, "food": 1500000, "tickets": 500000, "other": None},
                "flexibility": "MODERATE",
            },
            "preferences": {
                "travel_style": ["Nghỉ dưỡng", "Ẩm thực"],
                "interests": ["Biển", "Chụp ảnh"],
                "transport": {"preferred": ["Xe máy"], "available": [], "avoid": []},
                "accommodation": {"type_preferred": ["Khách sạn gần biển"], "location_preference": "Gần biển Mỹ Khê", "must_have_amenities": [], "avoid": []},
                "food": {"interested_in": ["Hải sản"], "dietary_restrictions": [], "disliked_foods": [], "preferred_price_range": "Bình dân"},
                "activities": {"preferred": ["Tắm biển", "Ngắm cảnh"], "avoided": [], "activity_intensity": "MODERATE"},
            },
            "place_requirements": {
                "must_visit": [{"name": "Bà Nà Hills", "reason": "Muốn đi", "priority": "HIGH"}, {"name": "Hội An", "reason": "Dạo phố cổ", "priority": "HIGH"}],
                "preferred": [],
                "excluded": [],
                "place_categories_to_include": [],
                "place_categories_to_avoid": [],
            },
            "schedule_constraints": {
                "pace": "RELAXED",
                "max_activities_per_day": 3,
                "avoid_rushing": True,
            },
            "logistics": {"departure_location": "Hà Nội", "arrival_location": "Đà Nẵng"},
            "requirements": {"must_include": [], "must_avoid": [], "special_requests": []},
            "planning_state": {"is_ready_to_generate": True},
            "extraction_metadata": {"source": "CONVERSATION", "needs_review": False, "unresolved_conflicts": []},
        }

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = json.dumps(mock_raw)

        msg = Message(id=1, conversation_id=1, sender="USER", content="Mình muốn đi Đà Nẵng 3 ngày 2 đêm cùng bạn gái...")
        ctx = TripPlanningContextExtractionService.extract_from_conversation(
            conversation_history=[msg],
            llm=mock_llm,
        )

        self.assertEqual(ctx.trip.destination.city, "Đà Nẵng")
        self.assertEqual(ctx.trip.dates.duration_days, 3)
        self.assertEqual(ctx.trip.dates.nights, 2)
        self.assertEqual(ctx.trip.travelers.adults, 2)
        self.assertEqual(ctx.trip.travelers.group_type, "COUPLE")
        self.assertEqual(ctx.budget.total, 5000000.0)
        self.assertEqual(len(ctx.place_requirements.must_visit), 2)
        self.assertEqual(ctx.schedule_constraints.pace, "RELAXED")

    # -------------------------------------------------------------------------
    # Scenario 2: Tổng hợp thông tin từ nhiều lượt chat
    # -------------------------------------------------------------------------
    def test_scenario_02_synthesis_across_multiple_turns(self):
        """Scenario 2: Turn 1 -> Turn 2 -> Turn 3 accumulates into unified context."""
        # Turn 1
        ctx1 = TripPlanningContext()
        ctx1.trip.destination.city = "Đà Nẵng"
        ctx1 = TripPlanningContextExtractionService.evaluate_planning_readiness(ctx1)

        # Turn 2: User adds duration & companion
        extracted_turn2 = TripPlanningContext()
        extracted_turn2.trip.dates.duration_days = 3
        extracted_turn2.trip.dates.nights = 2
        extracted_turn2.trip.travelers.adults = 2
        extracted_turn2.trip.travelers.group_type = GroupTypeEnum.COUPLE

        ctx2 = TripPlanningContextExtractionService.merge_contexts(ctx1, extracted_turn2, last_message_id=2)
        self.assertEqual(ctx2.trip.destination.city, "Đà Nẵng")
        self.assertEqual(ctx2.trip.dates.duration_days, 3)
        self.assertEqual(ctx2.trip.travelers.adults, 2)

        # Turn 3: User adds budget
        extracted_turn3 = TripPlanningContext()
        extracted_turn3.budget.total = 4000000.0
        extracted_turn3.budget.scope = BudgetScopeEnum.TOTAL

        ctx3 = TripPlanningContextExtractionService.merge_contexts(ctx2, extracted_turn3, last_message_id=3)
        self.assertEqual(ctx3.trip.destination.city, "Đà Nẵng")
        self.assertEqual(ctx3.trip.dates.duration_days, 3)
        self.assertEqual(ctx3.trip.dates.nights, 2)
        self.assertEqual(ctx3.trip.travelers.adults, 2)
        self.assertEqual(ctx3.budget.total, 4000000.0)
        self.assertTrue(ctx3.planning_state.is_ready_to_generate)

    # -------------------------------------------------------------------------
    # Scenario 3: Cập nhật ngân sách, ngày đi hoặc điểm đến
    # -------------------------------------------------------------------------
    def test_scenario_03_update_existing_fields(self):
        """Scenario 3: Updating budget from 4m to 5m, duration from 3 to 4 days."""
        base_ctx = TripPlanningContext()
        base_ctx.trip.destination.city = "Đà Nẵng"
        base_ctx.trip.dates.duration_days = 3
        base_ctx.budget.total = 4000000.0

        # Update budget
        update_budget = TripPlanningContext()
        update_budget.budget.total = 5000000.0

        merged1 = TripPlanningContextExtractionService.merge_contexts(base_ctx, update_budget, last_message_id=4)
        self.assertEqual(merged1.budget.total, 5000000.0)
        self.assertEqual(merged1.trip.destination.city, "Đà Nẵng")

        # Update duration
        update_duration = TripPlanningContext()
        update_duration.trip.dates.duration_days = 4
        update_duration.trip.dates.nights = 3

        merged2 = TripPlanningContextExtractionService.merge_contexts(merged1, update_duration, last_message_id=5)
        self.assertEqual(merged2.trip.dates.duration_days, 4)
        self.assertEqual(merged2.trip.dates.nights, 3)
        self.assertEqual(merged2.budget.total, 5000000.0)

    # -------------------------------------------------------------------------
    # Scenario 4: Xóa địa điểm khỏi danh sách bắt buộc
    # -------------------------------------------------------------------------
    def test_scenario_04_remove_place_from_must_visit(self):
        """Scenario 4: If user says 'bỏ Bà Nà Hills đi', it is removed from must_visit."""
        base_ctx = TripPlanningContext()
        base_ctx.place_requirements.must_visit = [
            PlaceRequirementItem(name="Bà Nà Hills", priority="HIGH"),
            PlaceRequirementItem(name="Hội An", priority="HIGH"),
        ]

        extracted_removal = TripPlanningContext()
        extracted_removal.place_requirements.excluded = [
            PlaceRequirementItem(name="Bà Nà Hills", reason="Người dùng đổi ý không muốn đi"),
        ]

        merged = TripPlanningContextExtractionService.merge_contexts(base_ctx, extracted_removal, last_message_id=6)

        must_visit_names = [p.name for p in merged.place_requirements.must_visit]
        self.assertNotIn("Bà Nà Hills", must_visit_names)
        self.assertIn("Hội An", must_visit_names)
        self.assertEqual(len(merged.place_requirements.excluded), 1)
        self.assertEqual(merged.place_requirements.excluded[0].name, "Bà Nà Hills")

    # -------------------------------------------------------------------------
    # Scenario 5: Thiếu ngày đi hoặc ngân sách
    # -------------------------------------------------------------------------
    def test_scenario_05_missing_dates_or_budget(self):
        """Scenario 5: User only specifies destination, missing duration and budget."""
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"

        evaluated = TripPlanningContextExtractionService.evaluate_planning_readiness(ctx)

        # Cannot generate itinerary without duration
        self.assertFalse(evaluated.planning_state.is_ready_to_generate)
        missing_fields = [m.field for m in evaluated.planning_state.missing_information]
        self.assertIn("trip.dates.duration", missing_fields)
        self.assertIn("budget.total", missing_fields)

        # Check importance
        duration_missing = next(m for m in evaluated.planning_state.missing_information if m.field == "trip.dates.duration")
        self.assertEqual(duration_missing.importance, "HIGH")

    # -------------------------------------------------------------------------
    # Scenario 6: Conversation chỉ chứa câu hỏi du lịch thông thường
    # -------------------------------------------------------------------------
    def test_scenario_06_pure_general_tourism_qa(self):
        """Scenario 6: General questions like 'Bà Nà Hills ở đâu?' should not trigger planning extraction."""
        faq1 = "Bà Nà Hills ở đâu?"
        faq2 = "Giá vé cáp treo Bà Nà Hills bao nhiêu tiền?"
        faq3 = "Chùa Linh Ứng mở cửa mấy giờ?"

        self.assertFalse(TripPlanningContextExtractionService.is_planning_intent(faq1, None))
        self.assertFalse(TripPlanningContextExtractionService.is_planning_intent(faq2, None))
        self.assertFalse(TripPlanningContextExtractionService.is_planning_intent(faq3, None))

        # Planning intent should be recognized
        plan1 = "Mình muốn đi Đà Nẵng 3 ngày 2 đêm."
        plan2 = "Lên lịch trình du lịch Đà Nẵng giúp mình với."
        self.assertTrue(TripPlanningContextExtractionService.is_planning_intent(plan1, None))
        self.assertTrue(TripPlanningContextExtractionService.is_planning_intent(plan2, None))

    # -------------------------------------------------------------------------
    # Scenario 7: JSON sai schema, enum không hợp lệ hoặc dữ liệu không đúng kiểu
    # -------------------------------------------------------------------------
    def test_scenario_07_invalid_schema_and_malformed_json(self):
        """Scenario 7: Robust parsing and graceful normalization of malformed LLM responses."""
        # 1. Markdown wrapped JSON with case variations
        raw_llm_markdown = """
        ```json
        {
          "schema_version": "1.0",
          "trip": {
            "status": "draft",
            "destination": {
              "city": "Đà Nẵng",
              "destination_flexibility": "flexible"
            },
            "dates": {
              "start_date": "not-a-valid-date",
              "duration_days": -1
            }
          },
          "budget": {
            "total": "4000000 VND"
          }
        }
        ```
        """
        parsed = TripPlanningContextExtractionService._parse_json_from_llm(raw_llm_markdown)
        ctx = TripPlanningContext.model_validate(parsed)

        self.assertEqual(ctx.trip.destination.city, "Đà Nẵng")
        self.assertEqual(ctx.trip.destination.destination_flexibility, "FLEXIBLE")
        self.assertEqual(ctx.trip.status, "DRAFT")
        # Invalid date stripped to None
        self.assertIsNone(ctx.trip.dates.start_date)
        # Negative duration stripped to None
        self.assertIsNone(ctx.trip.dates.duration_days)
        # String budget parsed to float 4000000.0
        self.assertEqual(ctx.budget.total, 4000000.0)

    # -------------------------------------------------------------------------
    # Scenario 8: LLM trả về null cho trường đã có dữ liệu hợp lệ
    # -------------------------------------------------------------------------
    def test_scenario_08_null_received_for_existing_valid_field(self):
        """Scenario 8: Non-destructive merge preserves existing destination & budget when LLM returns null."""
        existing = TripPlanningContext()
        existing.trip.destination.city = "Đà Nẵng"
        existing.trip.dates.duration_days = 3
        existing.budget.total = 5000000.0

        # LLM only extracted an activity in a quick follow-up turn
        incomplete_extraction = TripPlanningContext()
        incomplete_extraction.trip.destination.city = None
        incomplete_extraction.trip.dates.duration_days = None
        incomplete_extraction.budget.total = None
        incomplete_extraction.preferences.interests = ["Tắm biển"]

        merged = TripPlanningContextExtractionService.merge_contexts(existing, incomplete_extraction, last_message_id=7)

        # Existing values are strictly preserved
        self.assertEqual(merged.trip.destination.city, "Đà Nẵng")
        self.assertEqual(merged.trip.dates.duration_days, 3)
        self.assertEqual(merged.budget.total, 5000000.0)
        self.assertEqual(merged.preferences.interests, ["Tắm biển"])

    # -------------------------------------------------------------------------
    # Scenario 9: Thông tin giữa các lượt chat mâu thuẫn
    # -------------------------------------------------------------------------
    def test_scenario_09_conflicting_information_unresolved(self):
        """Scenario 9: Unresolved conflicts prevent is_ready_to_generate and record questions."""
        ctx = TripPlanningContext()
        ctx.trip.destination.city = "Đà Nẵng"
        ctx.trip.dates.duration_days = 3
        ctx.extraction_metadata.unresolved_conflicts = [
            "Mâu thuẫn ngày đi: Tin nhắn 1 nói đi tháng 11, tin nhắn 3 nói đi tháng 12."
        ]
        ctx.planning_state.clarification_questions = [
            "Bạn dự định khởi hành chính xác vào ngày nào trong tháng 11 hay tháng 12?"
        ]

        evaluated = TripPlanningContextExtractionService.evaluate_planning_readiness(ctx)
        self.assertFalse(evaluated.planning_state.is_ready_to_generate)
        self.assertEqual(len(evaluated.extraction_metadata.unresolved_conflicts), 1)
        self.assertEqual(len(evaluated.planning_state.clarification_questions), 1)

    # -------------------------------------------------------------------------
    # Scenario 10: Conversation không tồn tại hoặc không thuộc người dùng hiện tại
    # -------------------------------------------------------------------------
    def test_scenario_10_unauthorized_conversation_access(self):
        """Scenario 10: User B cannot access User A's planning context (HTTP 403 / 404)."""
        with Session(engine) as session:
            conv_a = ConversationService.create_conversation(session=session, user_id=self.user_a_id, title="Trip A")
            conv_id = conv_a.id

            # Save draft trip for User A
            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"
            TripPlanningContextExtractionService.save_context_to_db(session, conv_id, self.user_a_id, ctx)

        # 1. Non-existent conversation
        resp_404 = self.client.get("/api/v1/trips/conversations/999999/planning-context", headers=self.headers_a)
        self.assertEqual(resp_404.status_code, 404)

        # 2. User B tries to access User A's conversation
        resp_403 = self.client.get(f"/api/v1/trips/conversations/{conv_id}/planning-context", headers=self.headers_b)
        self.assertEqual(resp_403.status_code, 403)

        # 3. User A accesses their own conversation -> 200 OK
        resp_200 = self.client.get(f"/api/v1/trips/conversations/{conv_id}/planning-context", headers=self.headers_a)
        self.assertEqual(resp_200.status_code, 200)
        self.assertEqual(resp_200.json()["trip"]["destination"]["city"], "Đà Nẵng")

    # -------------------------------------------------------------------------
    # Scenario 11: Request retry không tạo trip trùng lặp
    # -------------------------------------------------------------------------
    def test_scenario_11_retry_does_not_duplicate_trip(self):
        """Scenario 11: Retrying extraction on the same conversation updates the same draft trip."""
        with Session(engine) as session:
            conv = ConversationService.create_conversation(session=session, user_id=self.user_a_id, title="Test Retry")
            conv_id = conv.id

            msg1 = ConversationService.save_message(session=session, conversation_id=conv_id, sender="USER", content="Mình muốn đi Đà Nẵng 3 ngày.")

            # Turn 1
            ctx1 = TripPlanningContext()
            ctx1.trip.destination.city = "Đà Nẵng"
            ctx1.trip.dates.duration_days = 3
            TripPlanningContextExtractionService.save_context_to_db(session, conv_id, self.user_a_id, ctx1)

            # Turn 2 (Retry of same message or updated state)
            ctx2 = TripPlanningContext()
            ctx2.trip.destination.city = "Đà Nẵng"
            ctx2.trip.dates.duration_days = 3
            ctx2.budget.total = 5000000.0
            TripPlanningContextExtractionService.save_context_to_db(session, conv_id, self.user_a_id, ctx2)

            # Assert only ONE trip exists for this conversation
            trips = session.exec(select(Trip).where(Trip.conversation_id == conv_id)).all()
            self.assertEqual(len(trips), 1)
            self.assertEqual(trips[0].destination_city, "Đà Nẵng")

            # Assert preferences updated
            pref = session.exec(select(TripPreference).where(TripPreference.trip_id == trips[0].id)).first()
            self.assertIsNotNone(pref)
            self.assertEqual(float(pref.budget), 5000000.0)

    # -------------------------------------------------------------------------
    # Scenario 12: Extraction thất bại nhưng chat vẫn hoạt động
    # -------------------------------------------------------------------------
    def test_scenario_12_extraction_failure_does_not_break_chat(self):
        """Scenario 12: When LLM extraction throws an error, /rag/ask still returns 200 and saves chat messages."""
        with patch.object(TripPlanningContextExtractionService, "extract_from_conversation", side_effect=RuntimeError("LLM quota exceeded")):
            with patch("app.rag.chain.RAGChain.invoke", return_value={"answer": "Chào bạn, mình có thể giúp bạn!"}):
                resp = self.client.post(
                    "/api/v1/rag/ask",
                    json={"message": "Mình muốn đi Đà Nẵng 3 ngày 2 đêm."},
                    headers=self.headers_a,
                )

                self.assertEqual(resp.status_code, 200)
                data = resp.json()
                self.assertIn("conversation_id", data)
                self.assertEqual(data["message"]["content"], "Chào bạn, mình có thể giúp bạn!")

    # -------------------------------------------------------------------------
    # Scenario 13: Database transaction thất bại không để dữ liệu không nhất quán
    # -------------------------------------------------------------------------
    def test_scenario_13_transaction_rollback_consistency(self):
        """Scenario 13: Failure during save_context_to_db rolls back changes cleanly."""
        with Session(engine) as session:
            conv = ConversationService.create_conversation(session=session, user_id=self.user_a_id, title="Test Tx")
            conv_id = conv.id

            initial_trips_count = len(session.exec(select(Trip).where(Trip.conversation_id == conv_id)).all())

            ctx = TripPlanningContext()
            ctx.trip.destination.city = "Đà Nẵng"

            # Force commit failure
            with patch.object(session, "commit", side_effect=Exception("Database lock error")):
                try:
                    TripPlanningContextExtractionService.save_context_to_db(session, conv_id, self.user_a_id, ctx)
                except Exception:
                    session.rollback()

            # Confirm rollback left no half-baked trip committed
            final_trips = session.exec(select(Trip).where(Trip.conversation_id == conv_id)).all()
            self.assertEqual(len(final_trips), initial_trips_count)


if __name__ == "__main__":
    unittest.main()
