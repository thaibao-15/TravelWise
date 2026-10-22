from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlmodel import Session

from app.api.deps import get_session
from app.schemas.weather import WeatherResponse
from app.services.weather_service import WeatherService

router = APIRouter(
    prefix="/api/v1/weather",
    tags=["Weather"],
)


@router.get("", response_model=WeatherResponse)
async def get_weather(
    latitude: Annotated[float, Query(ge=-90, le=90)],
    longitude: Annotated[float, Query(ge=-180, le=180)],
    forecast_days: Annotated[int, Query(ge=1, le=16)] = 7,
) -> WeatherResponse:
    """Lấy thời tiết hiện tại và dự báo theo ngày tại tọa độ."""
    return await WeatherService.get_forecast(latitude, longitude, forecast_days)


@router.get("/place/{place_id}", response_model=WeatherResponse)
async def get_place_weather(
    place_id: int,
    forecast_days: Annotated[int, Query(ge=1, le=16)] = 7,
    session: Session = Depends(get_session),
) -> WeatherResponse:
    """Lấy thời tiết tại tọa độ đã lưu của một địa điểm."""
    return await WeatherService.get_forecast_for_place(session, place_id, forecast_days)
