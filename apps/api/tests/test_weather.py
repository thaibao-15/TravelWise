import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi import HTTPException

from app.services.weather_service import WeatherService


def _open_meteo_payload(days: int = 7) -> dict:
    return {
        "timezone": "Asia/Ho_Chi_Minh",
        "current": {
            "time": "2026-10-18T12:00",
            "temperature_2m": 30.1,
            "apparent_temperature": 34.0,
            "relative_humidity_2m": 75,
            "is_day": 1,
            "precipitation": 0.2,
            "wind_speed_10m": 12.5,
            "weather_code": 2,
            "cloud_cover": 30,
            "pressure_msl": 1012,
            "wind_direction_10m": 180,
            "wind_gusts_10m": 20,
        },
        "hourly": {
            "time": ["2026-10-18T00:00", "2026-10-18T01:00"],
            "temperature_2m": [25.0, 25.2],
            "apparent_temperature": [26.0, 26.2],
            "precipitation_probability": [10, 10],
            "precipitation": [0.0, 0.0],
            "weather_code": [0, 0],
            "wind_speed_10m": [5.0, 5.2],
            "uv_index": [0.0, 0.0],
        },
        "daily": {
            "time": [f"2026-10-{18 + index:02d}" for index in range(days)],
            "temperature_2m_max": [31.0] * days,
            "temperature_2m_min": [25.0] * days,
            "apparent_temperature_max": [34.0] * days,
            "apparent_temperature_min": [26.0] * days,
            "sunrise": ["2026-10-18T05:45"] * days,
            "sunset": ["2026-10-18T17:30"] * days,
            "uv_index_max": [8.0] * days,
            "precipitation_sum": [0.2] * days,
            "precipitation_probability_max": [20] * days,
            "wind_speed_10m_max": [15.0] * days,
            "wind_gusts_10m_max": [25.0] * days,
            "weather_code": [2] * days,
        },
    }


class TestWeatherService(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        WeatherService._cache.clear()

    async def test_parses_current_and_daily_forecast(self) -> None:
        response = MagicMock()
        response.json.return_value = _open_meteo_payload()
        response.raise_for_status.return_value = None

        client = AsyncMock()
        client.get.return_value = response
        client.__aenter__.return_value = client

        with patch(
            "app.services.weather_service.httpx.AsyncClient",
            return_value=client,
        ):
            result = await WeatherService.get_forecast(16.0544, 108.2022)

        self.assertEqual(result.location.timezone, "Asia/Ho_Chi_Minh")
        self.assertEqual(result.current.apparent_temperature, 34.0)
        self.assertEqual(result.current.cloud_cover, 30)
        self.assertEqual(len(result.hourly), 2)
        self.assertEqual(len(result.forecast), 7)
        client.get.assert_awaited_once()

    async def test_uses_cache_for_same_coordinates(self) -> None:
        response = MagicMock()
        response.json.return_value = _open_meteo_payload()
        response.raise_for_status.return_value = None

        client = AsyncMock()
        client.get.return_value = response
        client.__aenter__.return_value = client

        with patch(
            "app.services.weather_service.httpx.AsyncClient",
            return_value=client,
        ):
            await WeatherService.get_forecast(16.0544, 108.2022)
            await WeatherService.get_forecast(16.0544, 108.2022)

        client.get.assert_awaited_once()

    async def test_rejects_invalid_response(self) -> None:
        response = MagicMock()
        response.json.return_value = {"timezone": "Asia/Ho_Chi_Minh"}
        response.raise_for_status.return_value = None

        client = AsyncMock()
        client.get.return_value = response
        client.__aenter__.return_value = client

        with patch(
            "app.services.weather_service.httpx.AsyncClient",
            return_value=client,
        ):
            with self.assertRaises(HTTPException) as raised:
                await WeatherService.get_forecast(16.0544, 108.2022)

        self.assertEqual(raised.exception.status_code, 502)
