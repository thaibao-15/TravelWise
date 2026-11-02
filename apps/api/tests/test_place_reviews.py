"""
Unit and integration test suite for Place Reviews and Review Images CRUD.

Tests cover:
1. Create review with rating, text, and nested images (POST /api/v1/places/{id}/reviews).
2. Verification of rating_avg and review_count cache on places table.
3. Validation: Rating outside [1, 5] rejected with 422.
4. Non-existent place rejected with 404.
5. Unauthorized request rejected with 401.
6. Duplicate review prevention (same user, same place) rejected with 409.
7. Add standalone review image (POST /api/v1/reviews/{id}/images).
8. Delete review image with permission check (DELETE /api/v1/reviews/images/{id}).
9. List reviews with pagination, star breakdown, and trip_type filter.
10. Toggle helpful vote (POST /api/v1/reviews/{id}/helpful) and self-vote rejection.
11. Update review (PUT /api/v1/reviews/{id}) with rating_avg recalculation.
12. Soft delete review (DELETE /api/v1/reviews/{id}) with rating_avg recalculation.
"""

from datetime import date
import unittest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.core.security import create_access_token
from app.db.session import engine
from app.main import app
from app.models.category import Category
from app.models.place import Place
from app.models.place_review import PlaceReview, ReviewHelpfulVote, ReviewImage
from app.models.user import User


class TestPlaceReviews(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            # Setup User 1 (Author)
            user1 = session.exec(select(User).where(User.email == "test_reviewer1@travelwise.vn")).first()
            if not user1:
                user1 = User(
                    email="test_reviewer1@travelwise.vn",
                    full_name="Reviewer One",
                    role="USER",
                    is_active=True,
                )
                session.add(user1)
                session.commit()
                session.refresh(user1)
            self.user1_id = user1.id

            # Setup User 2 (Voter)
            user2 = session.exec(select(User).where(User.email == "test_reviewer2@travelwise.vn")).first()
            if not user2:
                user2 = User(
                    email="test_reviewer2@travelwise.vn",
                    full_name="Reviewer Two",
                    role="USER",
                    is_active=True,
                )
                session.add(user2)
                session.commit()
                session.refresh(user2)
            self.user2_id = user2.id

            # Setup Category and Place for tests
            cat = session.exec(select(Category).where(Category.name == "Review Test Category")).first()
            if not cat:
                cat = Category(name="Review Test Category", description="Danh mục test")
                session.add(cat)
                session.commit()
                session.refresh(cat)

            place = session.exec(select(Place).where(Place.name == "Địa Điểm Test Review")).first()
            if not place:
                place = Place(
                    name="Địa Điểm Test Review",
                    description="Mô tả địa điểm dùng cho unit test review",
                    address="123 Đường Test, Đà Nẵng",
                    latitude=16.05,
                    longitude=108.20,
                    category_id=cat.id,
                    rating_avg=0.0,
                    review_count=0,
                    is_deleted=False,
                )
                session.add(place)
                session.commit()
                session.refresh(place)
            self.place_id = place.id

            # Clean any previous test reviews for this place to ensure fresh test state
            prev_reviews = session.exec(
                select(PlaceReview).where(PlaceReview.place_id == self.place_id)
            ).all()
            for r in prev_reviews:
                votes = session.exec(select(ReviewHelpfulVote).where(ReviewHelpfulVote.review_id == r.id)).all()
                for v in votes:
                    session.delete(v)
                imgs = session.exec(select(ReviewImage).where(ReviewImage.review_id == r.id)).all()
                for img in imgs:
                    session.delete(img)
                session.delete(r)

            place.rating_avg = 0.0
            place.review_count = 0
            session.add(place)
            session.commit()

        # Generate JWT Auth Tokens
        self.token_user1 = create_access_token(
            subject=self.user1_id, email="test_reviewer1@travelwise.vn", role="USER"
        )
        self.token_user2 = create_access_token(
            subject=self.user2_id, email="test_reviewer2@travelwise.vn", role="USER"
        )

        self.headers_user1 = {"Authorization": f"Bearer {self.token_user1}"}
        self.headers_user2 = {"Authorization": f"Bearer {self.token_user2}"}

    def tearDown(self):
        # Cleanup test data after tests
        with Session(engine) as session:
            test_reviews = session.exec(
                select(PlaceReview).where(PlaceReview.place_id == self.place_id)
            ).all()
            for r in test_reviews:
                votes = session.exec(select(ReviewHelpfulVote).where(ReviewHelpfulVote.review_id == r.id)).all()
                for v in votes:
                    session.delete(v)
                imgs = session.exec(select(ReviewImage).where(ReviewImage.review_id == r.id)).all()
                for img in imgs:
                    session.delete(img)
                session.delete(r)

            place = session.get(Place, self.place_id)
            if place:
                place.rating_avg = 0.0
                place.review_count = 0
                session.add(place)
            session.commit()

    # -------------------------------------------------------------------------
    # 1. Tạo đánh giá thành công kèm hình ảnh
    # -------------------------------------------------------------------------
    def test_01_create_review_with_images_success(self):
        """Tạo đánh giá 5 sao kèm 2 ảnh đính kèm và kiểm tra rating trên place."""
        payload = {
            "rating": 5,
            "title": "Chùa rất đẹp và thanh tịnh",
            "comment": "Không gian yên bình, view biển hùng vĩ tuyệt vời.",
            "trip_type": "family",
            "visited_at": "2026-10-10",
            "images": [
                {
                    "image_url": "https://example.com/photo1.jpg",
                    "caption": "Cổng vào",
                    "display_order": 1,
                },
                {
                    "image_url": "https://example.com/photo2.jpg",
                    "caption": "Tượng Bồ Tát",
                    "display_order": 2,
                },
            ],
        }

        resp = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json=payload,
            headers=self.headers_user1,
        )

        self.assertEqual(resp.status_code, 201)
        data = resp.json()
        self.assertEqual(data["rating"], 5)
        self.assertEqual(data["title"], "Chùa rất đẹp và thanh tịnh")
        self.assertEqual(data["trip_type"], "family")
        self.assertEqual(data["place_id"], self.place_id)
        self.assertEqual(data["user_id"], self.user1_id)
        self.assertEqual(len(data["images"]), 2)
        self.assertEqual(data["images"][0]["caption"], "Cổng vào")
        self.assertEqual(data["user"]["email"], "test_reviewer1@travelwise.vn")

        # Kiểm tra rating_avg và review_count trên bảng places được cập nhật
        with Session(engine) as session:
            place = session.get(Place, self.place_id)
            self.assertEqual(float(place.rating_avg), 5.0)
            self.assertEqual(place.review_count, 1)

    # -------------------------------------------------------------------------
    # 2. Kiểm tra validation số sao
    # -------------------------------------------------------------------------
    def test_02_create_review_invalid_rating(self):
        """Rating nhỏ hơn 1 hoặc lớn hơn 5 bị từ chối với 422."""
        payload = {
            "rating": 6,  # Không hợp lệ
            "comment": "Quá 5 sao",
        }
        resp = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json=payload,
            headers=self.headers_user1,
        )
        self.assertEqual(resp.status_code, 422)

    # -------------------------------------------------------------------------
    # 3. Yêu cầu đăng nhập (401)
    # -------------------------------------------------------------------------
    def test_03_create_review_unauthorized(self):
        """Tạo đánh giá mà không gửi Authorization header bị trả về 401."""
        payload = {"rating": 5, "comment": "Thử không đăng nhập"}
        resp = self.client.post(f"/api/v1/places/{self.place_id}/reviews", json=payload)
        self.assertIn(resp.status_code, [401, 403])

    # -------------------------------------------------------------------------
    # 4. Địa điểm không tồn tại (404)
    # -------------------------------------------------------------------------
    def test_04_create_review_place_not_found(self):
        """Tạo đánh giá cho place_id không tồn tại bị trả về 404."""
        payload = {"rating": 4, "comment": "Địa điểm ảo"}
        resp = self.client.post(
            "/api/v1/places/9999999/reviews",
            json=payload,
            headers=self.headers_user1,
        )
        self.assertEqual(resp.status_code, 404)

    def test_get_my_review_for_place(self):
        create_response = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json={"rating": 4, "comment": "Đánh giá của tôi"},
            headers=self.headers_user1,
        )
        self.assertEqual(create_response.status_code, 201)

        response = self.client.get(
            f"/api/v1/places/{self.place_id}/reviews/me",
            headers=self.headers_user1,
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["id"], create_response.json()["id"])
        self.assertEqual(response.json()["user_id"], self.user1_id)

        other_user_response = self.client.get(
            f"/api/v1/places/{self.place_id}/reviews/me",
            headers=self.headers_user2,
        )
        self.assertEqual(other_user_response.status_code, 200)
        self.assertIsNone(other_user_response.json())

    def test_get_my_review_for_place_returns_null_when_missing(self):
        response = self.client.get(
            f"/api/v1/places/{self.place_id}/reviews/me",
            headers=self.headers_user1,
        )

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json())

    def test_get_my_review_for_place_requires_authentication(self):
        response = self.client.get(
            f"/api/v1/places/{self.place_id}/reviews/me",
        )

        self.assertEqual(response.status_code, 401)

    # -------------------------------------------------------------------------
    # 5. Chống đánh giá trùng lặp (Duplicate review -> 409)
    # -------------------------------------------------------------------------
    def test_05_prevent_duplicate_review(self):
        """Một người chỉ được đánh giá 1 lần cho cùng 1 địa điểm."""
        payload = {"rating": 5, "comment": "Lần 1"}
        resp1 = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json=payload,
            headers=self.headers_user1,
        )
        self.assertEqual(resp1.status_code, 201)

        # Lần 2 từ cùng user1
        resp2 = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json=payload,
            headers=self.headers_user1,
        )
        self.assertEqual(resp2.status_code, 409)

    # -------------------------------------------------------------------------
    # 6. Thêm và Xóa ảnh riêng lẻ (ReviewImage CRUD)
    # -------------------------------------------------------------------------
    def test_06_review_images_add_and_delete(self):
        """Thêm một ảnh mới vào review đã tạo, sau đó xóa ảnh đó."""
        # Tạo review trước
        create_resp = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json={"rating": 4, "comment": "Đánh giá thử ảnh"},
            headers=self.headers_user1,
        )
        self.assertEqual(create_resp.status_code, 201)
        review_id = create_resp.json()["id"]

        # 1. Thêm ảnh mới
        img_payload = {
            "image_url": "https://example.com/standalone_photo.jpg",
            "caption": "Ảnh bổ sung",
            "display_order": 1,
        }
        add_img_resp = self.client.post(
            f"/api/v1/reviews/{review_id}/images",
            json=img_payload,
            headers=self.headers_user1,
        )
        self.assertEqual(add_img_resp.status_code, 201)
        img_data = add_img_resp.json()
        image_id = img_data["id"]
        self.assertEqual(img_data["caption"], "Ảnh bổ sung")

        # 2. User 2 cố xóa ảnh của User 1 -> 403
        del_img_forbidden = self.client.delete(
            f"/api/v1/reviews/images/{image_id}",
            headers=self.headers_user2,
        )
        self.assertEqual(del_img_forbidden.status_code, 403)

        # 3. User 1 xóa ảnh của chính mình -> 200
        del_img_success = self.client.delete(
            f"/api/v1/reviews/images/{image_id}",
            headers=self.headers_user1,
        )
        self.assertEqual(del_img_success.status_code, 200)

    # -------------------------------------------------------------------------
    # 7. Lấy danh sách đánh giá kèm thống kê và lọc
    # -------------------------------------------------------------------------
    def test_07_list_reviews_with_breakdown_and_filter(self):
        """Lấy danh sách đánh giá, kiểm tra phân bổ số sao và bộ lọc trip_type."""
        # User 1 đánh giá 5 sao (family)
        self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json={"rating": 5, "comment": "5 sao family", "trip_type": "family"},
            headers=self.headers_user1,
        )
        # User 2 đánh giá 3 sao (solo)
        self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json={"rating": 3, "comment": "3 sao solo", "trip_type": "solo"},
            headers=self.headers_user2,
        )

        # Lấy toàn bộ
        resp_all = self.client.get(f"/api/v1/places/{self.place_id}/reviews")
        self.assertEqual(resp_all.status_code, 200)
        data_all = resp_all.json()
        self.assertEqual(data_all["total"], 2)
        self.assertEqual(data_all["rating_avg"], 4.0)  # (5 + 3) / 2 = 4.0
        self.assertEqual(data_all["rating_breakdown"]["5"], 1)
        self.assertEqual(data_all["rating_breakdown"]["3"], 1)

        # Lọc chỉ lấy trip_type = 'family'
        resp_family = self.client.get(
            f"/api/v1/places/{self.place_id}/reviews?trip_type=family"
        )
        self.assertEqual(resp_family.status_code, 200)
        data_family = resp_family.json()
        self.assertEqual(data_family["total"], 1)
        self.assertEqual(data_family["items"][0]["trip_type"], "family")

    # -------------------------------------------------------------------------
    # 8. Bình chọn hữu ích (Helpful Vote)
    # -------------------------------------------------------------------------
    def test_08_toggle_helpful_vote(self):
        """Kiểm tra toggle like/unlike hữu ích và ngăn tác giả tự like bài mình."""
        create_resp = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json={"rating": 5, "comment": "Bài viết hay"},
            headers=self.headers_user1,
        )
        review_id = create_resp.json()["id"]

        # Tác giả tự like -> 400 Bad Request
        self_vote_resp = self.client.post(
            f"/api/v1/reviews/{review_id}/helpful",
            headers=self.headers_user1,
        )
        self.assertEqual(self_vote_resp.status_code, 400)

        # User 2 like lần 1 -> voted = True, helpful_count = 1
        vote1 = self.client.post(
            f"/api/v1/reviews/{review_id}/helpful",
            headers=self.headers_user2,
        )
        self.assertEqual(vote1.status_code, 200)
        self.assertTrue(vote1.json()["voted"])
        self.assertEqual(vote1.json()["helpful_count"], 1)

        # User 2 like lần 2 (bỏ like) -> voted = False, helpful_count = 0
        vote2 = self.client.post(
            f"/api/v1/reviews/{review_id}/helpful",
            headers=self.headers_user2,
        )
        self.assertEqual(vote2.status_code, 200)
        self.assertFalse(vote2.json()["voted"])
        self.assertEqual(vote2.json()["helpful_count"], 0)

    # -------------------------------------------------------------------------
    # 9. Cập nhật và Xóa đánh giá
    # -------------------------------------------------------------------------
    def test_09_update_and_delete_review(self):
        """Cập nhật điểm đánh giá và xóa mềm bài đánh giá."""
        create_resp = self.client.post(
            f"/api/v1/places/{self.place_id}/reviews",
            json={"rating": 5, "comment": "Ban đầu 5 sao"},
            headers=self.headers_user1,
        )
        review_id = create_resp.json()["id"]

        # Cập nhật thành 3 sao
        update_resp = self.client.put(
            f"/api/v1/reviews/{review_id}",
            json={"rating": 3, "comment": "Sửa lại thành 3 sao"},
            headers=self.headers_user1,
        )
        self.assertEqual(update_resp.status_code, 200)
        self.assertEqual(update_resp.json()["rating"], 3)

        # Kiểm tra rating trên place được tính lại
        with Session(engine) as session:
            place = session.get(Place, self.place_id)
            self.assertEqual(float(place.rating_avg), 3.0)

        # Xóa review
        del_resp = self.client.delete(
            f"/api/v1/reviews/{review_id}",
            headers=self.headers_user1,
        )
        self.assertEqual(del_resp.status_code, 200)

        # Sau khi xóa, place rating quay về 0
        with Session(engine) as session:
            place = session.get(Place, self.place_id)
            self.assertEqual(float(place.rating_avg), 0.0)
            self.assertEqual(place.review_count, 0)


if __name__ == "__main__":
    unittest.main()
