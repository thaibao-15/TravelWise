import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.routes.auth import router as auth_router
from app.api.routes.categories import router as categories_router
from app.api.routes.conversations import router as conversations_router
from app.api.routes.media import router as media_router
from app.api.routes.places import router as places_router
from app.api.routes.reviews import router as reviews_router
from app.api.routes.rag import router as rag_router
from app.api.routes.stt import router as stt_router
from app.api.routes.trips import router as trips_router
from app.api.routes.tts import router as tts_router
from app.api.routes.users import router as users_router
from app.api.routes.user_profile import router as user_profile_router
from app.api.routes.weather import router as weather_router

app = FastAPI(
    title="TravelWise API",
    description="TravelWise — Du lịch thông minh",
    version="0.1.0",
)

# CORS configuration for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static directory for media uploads and assets
static_dir = os.path.join(os.path.dirname(__file__), "static")
os.makedirs(os.path.join(static_dir, "uploads"), exist_ok=True)
app.mount("/static", StaticFiles(directory=static_dir), name="static")

app.include_router(auth_router)
app.include_router(users_router)
app.include_router(user_profile_router)
app.include_router(categories_router)
app.include_router(places_router)
app.include_router(reviews_router)
app.include_router(conversations_router)
app.include_router(rag_router)
app.include_router(trips_router)
app.include_router(stt_router)
app.include_router(tts_router)
app.include_router(weather_router)
app.include_router(media_router)