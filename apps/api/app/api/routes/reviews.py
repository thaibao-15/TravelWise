from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlmodel import Session

from app.api.deps import get_current_user, get_current_user_optional, get_session
from app.models.user import User
from app.schemas.place_review import (
    HelpfulVoteResponse,
    PlaceReviewCreate,
    PlaceReviewListResponse,
    PlaceReviewOwnerReply,
    PlaceReviewResponse,
    PlaceReviewUpdate,
    ReviewImageCreate,
    ReviewImageResponse,
)
from app.services.review_service import ReviewService

router = APIRouter(
    tags=["Reviews"],
)


# ─── Endpoints theo Địa điểm (Place Reviews) ──────────────────────────────────

@router.get(
    "/api/v1/places/{place_id}/reviews",
    response_model=PlaceReviewListResponse,
    summary="Lấy danh sách đánh giá của địa điểm",
)
def list_place_reviews(
    place_id: int,
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    rating: Optional[int] = Query(default=None, ge=1, le=5, description="Lọc theo số sao (1-5)"),
    trip_type: Optional[str] = Query(
        default=None,
        description="Lọc theo loại hình chuyến đi: solo, couple, family, friends, business",
    ),
    sort_by: str = Query(
        default="newest",
        pattern="^(newest|helpful|rating_high|rating_low)$",
        description="Sắp xếp: newest (mới nhất), helpful (hữu ích nhất), rating_high (sao cao), rating_low (sao thấp)",
    ),
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> PlaceReviewListResponse:
    """Lấy danh sách đánh giá của địa điểm có phân trang, bộ lọc và thống kê điểm số. Public."""
    user_id = current_user.id if current_user else None
    return ReviewService.list_reviews_for_place(
        session=session,
        place_id=place_id,
        current_user_id=user_id,
        skip=skip,
        limit=limit,
        rating=rating,
        trip_type=trip_type,
        sort_by=sort_by,
    )


@router.get(
    "/api/v1/places/{place_id}/reviews/me",
    response_model=Optional[PlaceReviewResponse],
    summary="Lấy đánh giá hiện có của người dùng cho địa điểm",
)
def get_my_place_review(
    place_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Optional[PlaceReviewResponse]:
    """Lấy đánh giá của người dùng hiện tại để hỗ trợ sửa thay vì tạo trùng."""
    return ReviewService.get_user_review_for_place(
        session=session,
        user_id=current_user.id,
        place_id=place_id,
    )


@router.post(
    "/api/v1/places/{place_id}/reviews",
    response_model=PlaceReviewResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Tạo đánh giá mới cho địa điểm",
)
def create_review(
    place_id: int,
    data: PlaceReviewCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> PlaceReviewResponse:
    """Đăng bài đánh giá mới kèm danh sách ảnh. Yêu cầu đăng nhập."""
    return ReviewService.create_review(
        session=session,
        user_id=current_user.id,
        place_id=place_id,
        data=data,
    )


# ─── Endpoints theo Đánh giá cụ thể (Review Actions) ──────────────────────────

@router.get(
    "/api/v1/reviews/{review_id}",
    response_model=PlaceReviewResponse,
    summary="Lấy chi tiết một bài đánh giá",
)
def get_review(
    review_id: int,
    session: Session = Depends(get_session),
    current_user: Optional[User] = Depends(get_current_user_optional),
) -> PlaceReviewResponse:
    """Lấy chi tiết đánh giá theo ID. Public."""
    user_id = current_user.id if current_user else None
    return ReviewService.get_review_by_id(
        session=session,
        review_id=review_id,
        current_user_id=user_id,
    )


@router.put(
    "/api/v1/reviews/{review_id}",
    response_model=PlaceReviewResponse,
    summary="Cập nhật bài đánh giá",
)
def update_review(
    review_id: int,
    data: PlaceReviewUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> PlaceReviewResponse:
    """Chỉnh sửa bài đánh giá của chính mình. Yêu cầu đăng nhập."""
    is_admin = current_user.role == "ADMIN"
    return ReviewService.update_review(
        session=session,
        user_id=current_user.id,
        review_id=review_id,
        data=data,
        is_admin=is_admin,
    )


@router.delete(
    "/api/v1/reviews/{review_id}",
    summary="Xóa bài đánh giá",
)
def delete_review(
    review_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> dict:
    """Xóa bài đánh giá của chính mình (hoặc Admin xóa). Yêu cầu đăng nhập."""
    is_admin = current_user.role == "ADMIN"
    return ReviewService.delete_review(
        session=session,
        user_id=current_user.id,
        review_id=review_id,
        is_admin=is_admin,
    )


# ─── Endpoints Ảnh Đánh Giá (Review Images) ───────────────────────────────────

@router.post(
    "/api/v1/reviews/{review_id}/images",
    response_model=ReviewImageResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Thêm ảnh vào bài đánh giá",
)
def add_review_image(
    review_id: int,
    data: ReviewImageCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> ReviewImageResponse:
    """Thêm một hình ảnh vào bài đánh giá của mình. Yêu cầu đăng nhập."""
    is_admin = current_user.role == "ADMIN"
    return ReviewService.add_review_image(
        session=session,
        user_id=current_user.id,
        review_id=review_id,
        data=data,
        is_admin=is_admin,
    )


@router.delete(
    "/api/v1/reviews/images/{image_id}",
    summary="Xóa một ảnh trong bài đánh giá",
)
def delete_review_image(
    image_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> dict:
    """Xóa một hình ảnh khỏi bài đánh giá. Yêu cầu đăng nhập."""
    is_admin = current_user.role == "ADMIN"
    return ReviewService.delete_review_image(
        session=session,
        user_id=current_user.id,
        image_id=image_id,
        is_admin=is_admin,
    )


# ─── Endpoints Tương Tác: Helpful Vote & Owner Reply ──────────────────────────

@router.post(
    "/api/v1/reviews/{review_id}/helpful",
    response_model=HelpfulVoteResponse,
    summary="Bình chọn hoặc hủy bình chọn hữu ích (Like / Helpful)",
)
def toggle_helpful_vote(
    review_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> HelpfulVoteResponse:
    """Bấm thích (Hữu ích) hoặc bỏ thích cho một bài nhận xét. Yêu cầu đăng nhập."""
    return ReviewService.toggle_helpful_vote(
        session=session,
        user_id=current_user.id,
        review_id=review_id,
    )


@router.post(
    "/api/v1/reviews/{review_id}/reply",
    response_model=PlaceReviewResponse,
    summary="Chủ địa điểm hoặc Quản trị viên phản hồi bài đánh giá",
)
def reply_to_review(
    review_id: int,
    data: PlaceReviewOwnerReply,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> PlaceReviewResponse:
    """Chủ cơ sở hoặc Quản trị viên phản hồi lại nhận xét. Yêu cầu quyền ADMIN hoặc MANAGER."""
    return ReviewService.reply_to_review(
        session=session,
        review_id=review_id,
        reply_text=data.owner_reply,
        current_user=current_user,
    )
