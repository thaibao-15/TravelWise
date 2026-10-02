from typing import Optional
from pydantic import BaseModel, ConfigDict


class CategoryResponse(BaseModel):
    id: int
    name: Optional[str] = None
    description: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class CategoryCreate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
