from fastapi import FastAPI

from app.api.routes.auth import router as auth_router
from app.api.routes.categories import router as categories_router
from app.api.routes.places import router as places_router
from app.api.routes.rag import router as rag_router
from app.api.routes.users import router as users_router

app = FastAPI(
    title="TravelWise API",
    description="TravelWise — Du lịch thông minh",
    version="0.1.0",
)

app.include_router(auth_router)
app.include_router(users_router)
app.include_router(categories_router)
app.include_router(places_router)
app.include_router(rag_router)
app.include_router(rag_router, prefix="/api/v1")

