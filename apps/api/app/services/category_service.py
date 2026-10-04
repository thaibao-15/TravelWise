from typing import List

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.models.category import Category
from app.schemas.category import CategoryCreate


class CategoryService:
    @staticmethod
    def list_categories(session: Session) -> List[Category]:
        return list(session.exec(select(Category)).all())

    @staticmethod
    def get_category_by_id(session: Session, category_id: int) -> Category:
        category = session.get(Category, category_id)
        if not category:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Category with id {category_id} not found",
            )
        return category

    @staticmethod
    def create_category(session: Session, data: CategoryCreate) -> Category:
        category = Category(
            name=data.name,
            description=data.description,
        )
        session.add(category)
        session.commit()
        session.refresh(category)
        return category
