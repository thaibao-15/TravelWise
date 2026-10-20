import asyncio
import logging
import time
from dataclasses import dataclass
from typing import Any

import httpx
from fastapi import HTTPException, status
from sqlmodel import Session

from app.core.config import settings
from app.schemas.weather import (
    CurrentWeather,
    DailyForecast,
    HourlyForecast,
    WeatherLocation,
    WeatherResponse,
)
from app.services.place_service import PlaceService

logger = logging.getLogger(__name__)


@dataclass
class _CacheEntry:
    expires_at: float
    value: WeatherResponse


class WeatherService:
    _cache: dict[tuple[float, float, int], _CacheEntry] = {}
    _cache_lock = asyncio.Lock()

    @classmethod
    async def get_forecast(
        cls,
        latitude: float,
        longitude: float,
        forecast_days: int = 7,
    ) -> WeatherResponse:
        cache_key = (round(latitude, 4), round(longitude, 4), forecast_days)
        now = time.monotonic()
        async with cls._cache_lock:
            cached = cls._cache.get(cache_key)
            if cached and cached.expires_at > now:
                return cached.value
            if cached:
                del cls._cache[cache_key]

        params = {
            "latitude": latitude,
            "longitude": longitude,
            "current": (
                "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,"
                "precipitation,weather_code,cloud_cover,pressure_msl,"
                "wind_speed_10m,wind_direction_10m,wind_gusts_10m"
            ),
            "hourly": (
                "temperature_2m,apparent_temperature,precipitation_probability,"
                "precipitation,weather_code,wind_speed_10m,uv_index"
            ),
            "daily": (
                "weather_code,temperature_2m_max,temperature_2m_min,"
                "apparent_temperature_max,apparent_temperature_min,sunrise,sunset,"
                "uv_index_max,precipitation_sum,precipitation_probability_max,"
                "wind_speed_10m_max,wind_gusts_10m_max"
            ),
            "forecast_days": forecast_days,
            "timezone": settings.WEATHER_TIMEZONE,
        }

        try:
            async with httpx.AsyncClient(
                timeout=settings.WEATHER_HTTP_TIMEOUT_SECONDS
            ) as client:
                response = await client.get(settings.OPEN_METEO_FORECAST_URL, params=params)
                response.raise_for_status()
                payload = response.json()
        except httpx.TimeoutException as exc:
            logger.warning("Open-Meteo request timed out: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail="Weather service timed out",
            ) from exc
        except httpx.HTTPStatusError as exc:
            logger.warning("Open-Meteo returned HTTP %s", exc.response.status_code)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Weather service returned an error",
            ) from exc
        except httpx.RequestError as exc:
            logger.warning("Open-Meteo request failed: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Weather service is unavailable",
            ) from exc
        except ValueError as exc:
            logger.warning("Open-Meteo returned invalid JSON: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Weather service returned invalid data",
            ) from exc

        try:
            weather = cls._parse_response(payload, latitude, longitude, forecast_days)
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            logger.warning("Invalid Open-Meteo response shape: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Weather service returned invalid data",
            ) from exc

        async with cls._cache_lock:
            cls._cache[cache_key] = _CacheEntry(
                expires_at=time.monotonic() + settings.WEATHER_CACHE_TTL_SECONDS,
                value=weather,
            )
        return weather

    @classmethod
    async def get_forecast_for_place(
        cls, session: Session, place_id: int, forecast_days: int = 7
    ) -> WeatherResponse:
        place = PlaceService.get_place_by_id(session, place_id)
        if place.latitude is None or place.longitude is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Place with id {place_id} does not have valid coordinates",
            )
        return await cls.get_forecast(place.latitude, place.longitude, forecast_days)

    @staticmethod
    def _parse_response(
        payload: dict[str, Any],
        latitude: float,
        longitude: float,
        forecast_days: int,
    ) -> WeatherResponse:
        current = payload["current"]
        hourly = payload["hourly"]
        daily = payload["daily"]
        dates = daily["time"]
        if len(dates) != forecast_days:
            raise ValueError("Unexpected forecast length")

        hourly_forecast = [
            HourlyForecast(
                time=hourly["time"][index],
                temperature=hourly["temperature_2m"][index],
                apparent_temperature=hourly["apparent_temperature"][index],
                precipitation_probability=hourly["precipitation_probability"][index],
                precipitation=hourly["precipitation"][index],
                weather_code=hourly["weather_code"][index],
                wind_speed=hourly["wind_speed_10m"][index],
                uv_index=hourly["uv_index"][index],
            )
            for index in range(len(hourly["time"]))
        ]
        if not hourly_forecast:
            raise ValueError("Hourly forecast is empty")

        forecast = [
            DailyForecast(
                date=dates[index],
                temperature_max=daily["temperature_2m_max"][index],
                temperature_min=daily["temperature_2m_min"][index],
                apparent_temperature_max=daily["apparent_temperature_max"][index],
                apparent_temperature_min=daily["apparent_temperature_min"][index],
                sunrise=daily["sunrise"][index],
                sunset=daily["sunset"][index],
                uv_index_max=daily["uv_index_max"][index],
                precipitation_sum=daily["precipitation_sum"][index],
                precipitation_probability=daily["precipitation_probability_max"][index],
                wind_speed_max=daily["wind_speed_10m_max"][index],
                wind_gusts_max=daily["wind_gusts_10m_max"][index],
                weather_code=daily["weather_code"][index],
            )
            for index in range(forecast_days)
        ]
        return WeatherResponse(
            location=WeatherLocation(
                latitude=latitude,
                longitude=longitude,
                timezone=payload["timezone"],
            ),
            current=CurrentWeather(
                time=current["time"],
                temperature=current["temperature_2m"],
                apparent_temperature=current["apparent_temperature"],
                relative_humidity=current["relative_humidity_2m"],
                is_day=current["is_day"],
                precipitation=current["precipitation"],
                weather_code=current["weather_code"],
                cloud_cover=current["cloud_cover"],
                pressure_msl=current["pressure_msl"],
                wind_speed=current["wind_speed_10m"],
                wind_direction=current["wind_direction_10m"],
                wind_gusts=current["wind_gusts_10m"],
            ),
            hourly=hourly_forecast,
            forecast=forecast,
        )
