from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class KnowledgeResponse(BaseModel):
    id: int
    place_id: Optional[int] = None
    title: Optional[str] = None
    content: Optional[str] = None
    source: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class KnowledgeCreate(BaseModel):
    place_id: int
    title: Optional[str] = None
    content: Optional[str] = None
    source: Optional[str] = None
