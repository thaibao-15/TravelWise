from enum import Enum
from typing import Optional
from pydantic import BaseModel, ConfigDict


class ChatMediaType(str, Enum):
    IMAGE = "image"
    VIDEO = "video"


class ChatMediaResponse(BaseModel):
    id: str
    type: ChatMediaType
    url: str
    thumbnail_url: Optional[str] = None
    title: Optional[str] = None
    file_size: Optional[int] = None
    mime_type: Optional[str] = None

    model_config = ConfigDict(from_attributes=True, use_enum_values=True)
