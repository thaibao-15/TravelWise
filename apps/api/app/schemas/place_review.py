from datetime import date, datetime
from typing import Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field


class ReviewImageCreate(BaseModel):
    image_url: str = Field(..., max_length=2048, description="URL hình ảnh đính kèm")
    caption: Optional[str] = Field(None, max_length=255, description="Chú thích hình ảnh")
    display_order: int = Field(0, description="Thứ tự hiển thị ảnh")


class ReviewImageResponse(BaseModel):
    id: int
    review_id: int
    image_url: str
    caption: Optional[str] = None
    display_order: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ReviewAuthorResponse(BaseModel):
    id: int
    email: str
    full_name: Optional[str] = None
    avatar_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class PlaceReviewCreate(BaseModel):
    rating: int = Field(..., ge=1, le=5, description="Điểm đánh giá từ 1 đến 5 sao")
    title: Optional[str] = Field(None, max_length=255, description="Tiêu đề bài nhận xét")
    comment: Optional[str] = Field(None, description="Nội dung đánh giá chi tiết")
    trip_type: Optional[str] = Field(
        None,
        max_length=20,
        description="Ngữ cảnh chuyến đi: solo, couple, family, friends, business",
    )
    visited_at: Optional[date] = Field(None, description="Thời điểm thực tế trải nghiệm")
    images: Optional[List[ReviewImageCreate]] = Field(default=[], description="Danh sách ảnh đính kèm")


class PlaceReviewUpdate(BaseModel):
    rating: Optional[int] = Field(None, ge=1, le=5, description="Điểm đánh giá từ 1 đến 5 sao")
    title: Optional[str] = Field(None, max_length=255, description="Tiêu đề bài nhận xét")
    comment: Optional[str] = Field(None, description="Nội dung đánh giá chi tiết")
    trip_type: Optional[str] = Field(None, max_length=20)
    visited_at: Optional[date] = None


class PlaceReviewOwnerReply(BaseModel):
    owner_reply: str = Field(..., min_length=1, description="Nội dung phản hồi của chủ địa điểm hoặc admin")


class PlaceReviewResponse(BaseModel):
    id: int
    place_id: int
    user_id: int
    rating: int
    title: Optional[str] = None
    comment: Optional[str] = None
    trip_type: Optional[str] = None
    visited_at: Optional[date] = None
    helpful_count: int = 0
    owner_reply: Optional[str] = None
    owner_replied_at: Optional[datetime] = None
    is_visible: bool
    created_at: datetime
    updated_at: datetime
    images: List[ReviewImageResponse] = []
    user: Optional[ReviewAuthorResponse] = None
    is_helpful_voted: Optional[bool] = False

    model_config = ConfigDict(from_attributes=True)


class PlaceReviewListResponse(BaseModel):
    total: int
    rating_avg: float
    rating_breakdown: Dict[int, int]
    items: List[PlaceReviewResponse]


class HelpfulVoteResponse(BaseModel):
    review_id: int
    voted: bool
    helpful_count: int
    message: str
