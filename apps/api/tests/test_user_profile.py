import unittest
from datetime import date, timedelta
from decimal import Decimal
from unittest.mock import patch

from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlmodel import Session, SQLModel, select

from app.main import app
from app.models.user import User
from app.models.user_profile import UserProfile
from app.schemas.user_profile import UserProfileCreate, UserProfileUpdate
from app.services.user_profile_service import UserProfileService


class TestUserProfileService(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}
        )
        SQLModel.metadata.create_all(cls.engine)

    def setUp(self):
        with Session(self.engine) as session:
            user = User(email=f"profile-{id(self)}@example.com")
            session.add(user)
            session.commit()
            session.refresh(user)
            self.user_id = user.id

    def test_get_missing_profile_returns_404(self):
        with (
            Session(self.engine) as session,
            self.assertRaises(HTTPException) as context,
        ):
            UserProfileService.get_profile(session, self.user_id)
        self.assertEqual(context.exception.status_code, 404)

    def test_create_profile_serializes_and_returns_json_arrays(self):
        payload = UserProfileCreate(
            phone="0900000000",
            favorite_categories=["Biển", "Ẩm thực"],
            interests=["nhiếp ảnh"],
            budget_min=Decimal(1000000),
            budget_max=Decimal(5000000),
        )

        with Session(self.engine) as session:
            result = UserProfileService.create_profile(session, self.user_id, payload)
            stored = session.exec(
                select(UserProfile).where(UserProfile.user_id == self.user_id)
            ).one()

        self.assertEqual(result.favorite_categories, ["Biển", "Ẩm thực"])
        self.assertEqual(stored.favorite_categories, '["Biển", "Ẩm thực"]')
        self.assertEqual(result.budget_max, Decimal("5000000.00"))

    def test_duplicate_create_returns_409(self):
        payload = UserProfileCreate()
        with Session(self.engine) as session:
            UserProfileService.create_profile(session, self.user_id, payload)
            with self.assertRaises(HTTPException) as context:
                UserProfileService.create_profile(session, self.user_id, payload)
        self.assertEqual(context.exception.status_code, 409)

    def test_update_revalidates_full_budget_range_and_allows_null(self):
        with Session(self.engine) as session:
            UserProfileService.create_profile(
                session,
                self.user_id,
                UserProfileCreate(
                    budget_min=Decimal(100),
                    budget_max=Decimal(500),
                    interests=["biển"],
                ),
            )
            with self.assertRaises(HTTPException) as context:
                UserProfileService.update_profile(
                    session,
                    self.user_id,
                    UserProfileUpdate(budget_min=Decimal(600)),
                )
            self.assertEqual(context.exception.status_code, 422)
            result = UserProfileService.update_profile(
                session,
                self.user_id,
                UserProfileUpdate(interests=None),
            )

        self.assertIsNone(result.interests)

    def test_future_birth_date_and_negative_budget_are_rejected(self):
        with self.assertRaises(ValueError):
            UserProfileCreate(date_of_birth=date.today() + timedelta(days=1))
        with self.assertRaises(ValueError):
            UserProfileCreate(budget_min=Decimal(-1))

    @patch("app.services.user_profile_service.UserProfileService.get_profile")
    def test_update_missing_profile_uses_not_found(self, get_profile):
        get_profile.side_effect = HTTPException(status_code=404)
        with (
            Session(self.engine) as session,
            self.assertRaises(HTTPException) as context,
        ):
            UserProfileService.update_profile(
                session, self.user_id, UserProfileUpdate()
            )
        self.assertEqual(context.exception.status_code, 404)


class TestUserProfileAuthentication(unittest.TestCase):
    def test_profile_requires_authentication(self):
        response = TestClient(app).get("/api/v1/users/me/profile")
        self.assertEqual(response.status_code, 401)
