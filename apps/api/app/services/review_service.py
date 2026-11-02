from typing import Dict, List, Optional
from fastapi import HTTPException, status
from sqlalchemy.orm import selectinload
from sqlmodel import Session, func, select

from app.db.base import _utcnow
from app.models.place import Place
from app.models.place_review import PlaceReview, ReviewHelpfulVote, ReviewImage
from app.models.user import User
from app.schemas.place_review import (
    HelpfulVoteResponse,
    PlaceReviewCreate,
    PlaceReviewListResponse,
    PlaceReviewResponse,
    PlaceReviewUpdate,
    ReviewAuthorResponse,
    ReviewImageCreate,
    ReviewImageResponse,
)


class ReviewService:
    @staticmethod
    def _recalculate_place_rating(session: Session, place_id: int) -> None:
        """Tính toán lại rating_avg và review_count đệm trên bảng places."""
        stats = session.exec(
            select(
                func.avg(PlaceReview.rating),
                func.count(PlaceReview.id),
            ).where(
                PlaceReview.place_id == place_id,
                PlaceReview.is_visible == True,  # noqa: E712
                PlaceReview.is_deleted == False,  # noqa: E712
            )
        ).first()

        avg_val = round(float(stats[0]), 2) if stats and stats[0] is not None else 0.0
        count_val = int(stats[1]) if stats and stats[1] is not None else 0

        place = session.get(Place, place_id)
        if place:
            place.rating_avg = avg_val
            place.review_count = count_val
            session.add(place)

    @staticmethod
    def create_review(
        session: Session,
        user_id: int,
        place_id: int,
        data: PlaceReviewCreate,
    ) -> PlaceReviewResponse:
        """Tạo đánh giá mới cho địa điểm (mỗi user chỉ đánh giá 1 lần)."""
        place = session.get(Place, place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy địa điểm với ID {place_id}",
            )

        # Kiểm tra xem user đã đánh giá chưa
        existing = session.exec(
            select(PlaceReview).where(
                PlaceReview.place_id == place_id,
                PlaceReview.user_id == user_id,
                PlaceReview.is_deleted == False,  # noqa: E712
            )
        ).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Bạn đã đánh giá địa điểm này rồi. Vui lòng chỉnh sửa đánh giá hiện có.",
            )

        review = PlaceReview(
            user_id=user_id,
            place_id=place_id,
            rating=data.rating,
            title=data.title,
            comment=data.comment,
            trip_type=data.trip_type,
            visited_at=data.visited_at,
            is_visible=True,
            is_deleted=False,
            helpful_count=0,
        )
        session.add(review)
        session.flush()

        # Thêm hình ảnh nếu có
        if data.images:
            for idx, img in enumerate(data.images):
                img_record = ReviewImage(
                    review_id=review.id,
                    image_url=img.image_url,
                    caption=img.caption,
                    display_order=img.display_order if img.display_order != 0 else idx,
                )
                session.add(img_record)

        session.flush()
        ReviewService._recalculate_place_rating(session, place_id)
        session.commit()
        session.refresh(review)

        return ReviewService.get_review_by_id(session, review.id, current_user_id=user_id)

    @staticmethod
    def get_review_by_id(
        session: Session,
        review_id: int,
        current_user_id: Optional[int] = None,
    ) -> PlaceReviewResponse:
        """Lấy chi tiết một bài đánh giá kèm hình ảnh và thông tin tác giả."""
        statement = (
            select(PlaceReview)
            .where(
                PlaceReview.id == review_id,
                PlaceReview.is_deleted == False,  # noqa: E712
            )
            .options(
                selectinload(PlaceReview.images),
                selectinload(PlaceReview.user),
            )
        )
        review = session.exec(statement).first()
        if not review:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đánh giá với ID {review_id}",
            )

        # Kiểm tra xem current user đã vote helpful chưa
        is_voted = False
        if current_user_id:
            vote = session.exec(
                select(ReviewHelpfulVote).where(
                    ReviewHelpfulVote.review_id == review_id,
                    ReviewHelpfulVote.user_id == current_user_id,
                )
            ).first()
            is_voted = vote is not None

        return PlaceReviewResponse(
            id=review.id,
            place_id=review.place_id,
            user_id=review.user_id,
            rating=review.rating,
            title=review.title,
            comment=review.comment,
            trip_type=review.trip_type,
            visited_at=review.visited_at,
            helpful_count=review.helpful_count,
            owner_reply=review.owner_reply,
            owner_replied_at=review.owner_replied_at,
            is_visible=review.is_visible,
            created_at=review.created_at,
            updated_at=review.updated_at,
            images=[ReviewImageResponse.model_validate(img) for img in sorted(review.images, key=lambda x: x.display_order)],
            user=ReviewAuthorResponse.model_validate(review.user) if review.user else None,
            is_helpful_voted=is_voted,
        )

    @staticmethod
    def get_user_review_for_place(
        session: Session,
        user_id: int,
        place_id: int,
    ) -> Optional[PlaceReviewResponse]:
        """Lấy đánh giá hiện có của người dùng cho một địa điểm."""
        place = session.get(Place, place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy địa điểm với ID {place_id}",
            )

        review = session.exec(
            select(PlaceReview.id).where(
                PlaceReview.place_id == place_id,
                PlaceReview.user_id == user_id,
                PlaceReview.is_deleted == False,  # noqa: E712
            )
        ).first()
        if review is None:
            return None

        return ReviewService.get_review_by_id(
            session,
            review,
            current_user_id=user_id,
        )

    @staticmethod
    def list_reviews_for_place(
        session: Session,
        place_id: int,
        current_user_id: Optional[int] = None,
        skip: int = 0,
        limit: int = 20,
        rating: Optional[int] = None,
        trip_type: Optional[str] = None,
        sort_by: str = "newest",
    ) -> PlaceReviewListResponse:
        """Lấy danh sách đánh giá của một địa điểm có phân trang, lọc và thống kê điểm."""
        # 1. Thống kê tổng quan cho place
        place = session.get(Place, place_id)
        if not place or place.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy địa điểm với ID {place_id}",
            )

        base_filter = [
            PlaceReview.place_id == place_id,
            PlaceReview.is_visible == True,  # noqa: E712
            PlaceReview.is_deleted == False,  # noqa: E712
        ]

        # Đếm phân bổ số sao (1 đến 5 sao)
        breakdown_query = (
            select(PlaceReview.rating, func.count(PlaceReview.id))
            .where(*base_filter)
            .group_by(PlaceReview.rating)
        )
        breakdown_rows = session.exec(breakdown_query).all()
        rating_breakdown: Dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
        total_count = 0
        sum_rating = 0
        for star, count in breakdown_rows:
            rating_breakdown[star] = count
            total_count += count
            sum_rating += star * count

        rating_avg = round(sum_rating / total_count, 2) if total_count > 0 else 0.0

        # 2. Xây dựng query danh sách có filter và sort
        query_filters = list(base_filter)
        if rating is not None:
            query_filters.append(PlaceReview.rating == rating)
        if trip_type:
            query_filters.append(PlaceReview.trip_type == trip_type)

        stmt = (
            select(PlaceReview)
            .where(*query_filters)
            .options(
                selectinload(PlaceReview.images),
                selectinload(PlaceReview.user),
            )
        )

        if sort_by == "helpful":
            stmt = stmt.order_by(PlaceReview.helpful_count.desc(), PlaceReview.created_at.desc())
        elif sort_by == "rating_high":
            stmt = stmt.order_by(PlaceReview.rating.desc(), PlaceReview.created_at.desc())
        elif sort_by == "rating_low":
            stmt = stmt.order_by(PlaceReview.rating.asc(), PlaceReview.created_at.desc())
        else:  # newest
            stmt = stmt.order_by(PlaceReview.created_at.desc())

        # Đếm tổng số kết quả khớp bộ lọc
        count_stmt = select(func.count(PlaceReview.id)).where(*query_filters)
        filtered_total = session.exec(count_stmt).one()

        reviews = list(session.exec(stmt.offset(skip).limit(limit)).all())

        # Tập hợp review_ids user đã vote helpful
        voted_review_ids = set()
        if current_user_id and reviews:
            rev_ids = [r.id for r in reviews]
            votes = session.exec(
                select(ReviewHelpfulVote.review_id).where(
                    ReviewHelpfulVote.user_id == current_user_id,
                    ReviewHelpfulVote.review_id.in_(rev_ids),
                )
            ).all()
            voted_review_ids = set(votes)

        items = [
            PlaceReviewResponse(
                id=r.id,
                place_id=r.place_id,
                user_id=r.user_id,
                rating=r.rating,
                title=r.title,
                comment=r.comment,
                trip_type=r.trip_type,
                visited_at=r.visited_at,
                helpful_count=r.helpful_count,
                owner_reply=r.owner_reply,
                owner_replied_at=r.owner_replied_at,
                is_visible=r.is_visible,
                created_at=r.created_at,
                updated_at=r.updated_at,
                images=[ReviewImageResponse.model_validate(img) for img in sorted(r.images, key=lambda x: x.display_order)],
                user=ReviewAuthorResponse.model_validate(r.user) if r.user else None,
                is_helpful_voted=r.id in voted_review_ids,
            )
            for r in reviews
        ]

        return PlaceReviewListResponse(
            total=filtered_total,
            rating_avg=rating_avg,
            rating_breakdown=rating_breakdown,
            items=items,
        )

    @staticmethod
    def update_review(
        session: Session,
        user_id: int,
        review_id: int,
        data: PlaceReviewUpdate,
        is_admin: bool = False,
    ) -> PlaceReviewResponse:
        """Cập nhật bài đánh giá (chỉ tác giả hoặc admin)."""
        review = session.get(PlaceReview, review_id)
        if not review or review.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đánh giá với ID {review_id}",
            )

        if review.user_id != user_id and not is_admin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền chỉnh sửa đánh giá này",
            )

        rating_changed = False
        if data.rating is not None and data.rating != review.rating:
            review.rating = data.rating
            rating_changed = True

        if data.title is not None:
            review.title = data.title
        if data.comment is not None:
            review.comment = data.comment
        if data.trip_type is not None:
            review.trip_type = data.trip_type
        if data.visited_at is not None:
            review.visited_at = data.visited_at

        review.updated_at = _utcnow()
        session.add(review)

        if rating_changed:
            session.flush()
            ReviewService._recalculate_place_rating(session, review.place_id)

        session.commit()
        session.refresh(review)
        return ReviewService.get_review_by_id(session, review.id, current_user_id=user_id)

    @staticmethod
    def delete_review(
        session: Session,
        user_id: int,
        review_id: int,
        is_admin: bool = False,
    ) -> dict:
        """Xóa mềm đánh giá và tính lại điểm trung bình."""
        review = session.get(PlaceReview, review_id)
        if not review or review.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đánh giá với ID {review_id}",
            )

        if review.user_id != user_id and not is_admin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền xóa đánh giá này",
            )

        review.is_deleted = True
        review.updated_at = _utcnow()
        session.add(review)
        session.flush()

        ReviewService._recalculate_place_rating(session, review.place_id)
        session.commit()

        return {"success": True, "message": "Đã xóa đánh giá thành công"}

    @staticmethod
    def add_review_image(
        session: Session,
        user_id: int,
        review_id: int,
        data: ReviewImageCreate,
        is_admin: bool = False,
    ) -> ReviewImageResponse:
        """Thêm hình ảnh vào một bài đánh giá hiện có."""
        review = session.get(PlaceReview, review_id)
        if not review or review.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đánh giá với ID {review_id}",
            )

        if review.user_id != user_id and not is_admin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền thêm ảnh vào đánh giá này",
            )

        image = ReviewImage(
            review_id=review_id,
            image_url=data.image_url,
            caption=data.caption,
            display_order=data.display_order,
        )
        session.add(image)
        session.commit()
        session.refresh(image)
        return ReviewImageResponse.model_validate(image)

    @staticmethod
    def delete_review_image(
        session: Session,
        user_id: int,
        image_id: int,
        is_admin: bool = False,
    ) -> dict:
        """Xóa một hình ảnh khỏi bài đánh giá."""
        image = session.get(ReviewImage, image_id)
        if not image:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy hình ảnh với ID {image_id}",
            )

        review = session.get(PlaceReview, image.review_id)
        if not review or (review.user_id != user_id and not is_admin):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền xóa hình ảnh này",
            )

        session.delete(image)
        session.commit()
        return {"success": True, "message": "Đã xóa hình ảnh thành công"}

    @staticmethod
    def reply_to_review(
        session: Session,
        review_id: int,
        reply_text: str,
        current_user: User,
    ) -> PlaceReviewResponse:
        """Chủ địa điểm hoặc Quản trị viên phản hồi lại bài đánh giá."""
        if current_user.role not in ["ADMIN", "MANAGER"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Chỉ người quản lý hoặc quản trị viên mới có quyền phản hồi đánh giá",
            )

        review = session.get(PlaceReview, review_id)
        if not review or review.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đánh giá với ID {review_id}",
            )

        review.owner_reply = reply_text
        review.owner_replied_at = _utcnow()
        review.updated_at = _utcnow()
        session.add(review)
        session.commit()
        session.refresh(review)

        return ReviewService.get_review_by_id(session, review.id, current_user_id=current_user.id)

    @staticmethod
    def toggle_helpful_vote(
        session: Session,
        user_id: int,
        review_id: int,
    ) -> HelpfulVoteResponse:
        """Bấm hoặc hủy bình chọn hữu ích (Helpful / Like) cho một bài nhận xét."""
        review = session.get(PlaceReview, review_id)
        if not review or review.is_deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đánh giá với ID {review_id}",
            )

        if review.user_id == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bạn không thể bình chọn hữu ích cho đánh giá của chính mình",
            )

        vote = session.exec(
            select(ReviewHelpfulVote).where(
                ReviewHelpfulVote.review_id == review_id,
                ReviewHelpfulVote.user_id == user_id,
            )
        ).first()

        if vote:
            # Hủy bình chọn
            session.delete(vote)
            review.helpful_count = max(0, review.helpful_count - 1)
            session.add(review)
            session.commit()
            return HelpfulVoteResponse(
                review_id=review_id,
                voted=False,
                helpful_count=review.helpful_count,
                message="Đã hủy bình chọn hữu ích",
            )
        else:
            # Thêm bình chọn
            new_vote = ReviewHelpfulVote(
                review_id=review_id,
                user_id=user_id,
            )
            session.add(new_vote)
            review.helpful_count += 1
            session.add(review)
            session.commit()
            return HelpfulVoteResponse(
                review_id=review_id,
                voted=True,
                helpful_count=review.helpful_count,
                message="Đã bình chọn đánh giá này hữu ích",
            )
