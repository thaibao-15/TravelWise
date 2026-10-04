from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


class ConversationCreate(BaseModel):
    title: Optional[str] = Field(
        default=None,
        max_length=255,
        description="Tiêu đề cuộc trò chuyện (tùy chọn)",
        examples=["Chuyến du lịch Đà Nẵng 3 ngày 2 đêm"],
    )


class MessageRead(BaseModel):
    id: int
    conversation_id: int
    sender: str
    content: str
    audio_url: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ConversationRead(BaseModel):
    id: int
    user_id: Optional[int] = None
    title: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ConversationDetail(ConversationRead):
    messages: List[MessageRead] = []

    model_config = ConfigDict(from_attributes=True)
