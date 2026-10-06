from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes.auth import router as auth_router
from app.api.routes.categories import router as categories_router
from app.api.routes.conversations import router as conversations_router
from app.api.routes.places import router as places_router
from app.api.routes.rag import router as rag_router
from app.api.routes.users import router as users_router

app = FastAPI(
    title="TravelWise API",
    description="TravelWise — Du lịch thông minh",
    version="0.1.0",
)

# CORS configuration for web application
# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=["http://localhost:3000", "http://127.0.0.1:3000", 
#                     "http://localhost:50249", "http://127.0.0.1:50249",],
#     allow_credentials=True,
#     allow_methods=["*"],
#     allow_headers=["*"],
# )

# CORS configuration for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(users_router)
app.include_router(categories_router)
app.include_router(places_router)
app.include_router(conversations_router)
app.include_router(rag_router)
