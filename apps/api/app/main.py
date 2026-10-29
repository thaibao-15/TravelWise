from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes.auth import router as auth_router
from app.api.routes.categories import router as categories_router
from app.api.routes.conversations import router as conversations_router
from app.api.routes.places import router as places_router
from app.api.routes.reviews import router as reviews_router
from app.api.routes.rag import router as rag_router
from app.api.routes.stt import router as stt_router
from app.api.routes.trips import router as trips_router
from app.api.routes.tts import router as tts_router
from app.api.routes.users import router as users_router
from app.api.routes.user_profile import router as user_profile_router
from app.api.routes.weather import router as weather_router

fastapi_app = FastAPI(
    title="TravelWise API",
    description="TravelWise — Du lịch thông minh",
    version="0.1.0",
)

# Keep CORS outside FastAPI's error middleware so unhandled 500 responses
# still include CORS headers and browsers can display the actual API error.
app = CORSMiddleware(
    app=fastapi_app,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

fastapi_app.include_router(auth_router)
fastapi_app.include_router(users_router)
fastapi_app.include_router(user_profile_router)
fastapi_app.include_router(categories_router)
fastapi_app.include_router(places_router)
fastapi_app.include_router(reviews_router)
fastapi_app.include_router(conversations_router)
fastapi_app.include_router(rag_router)
fastapi_app.include_router(trips_router)
fastapi_app.include_router(stt_router)
fastapi_app.include_router(tts_router)
fastapi_app.include_router(weather_router)
