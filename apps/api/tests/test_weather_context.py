import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

from app.schemas.weather import (
    CurrentWeather,
    DailyForecast,
    HourlyForecast,
    WeatherLocation,
    WeatherResponse,
)
from app.schemas.weather_intent import WeatherIntentType
from app.services.weather_context_service import WeatherContextService

VIETNAM_TZ = timezone(timedelta(hours=7), name="Asia/Ho_Chi_Minh")


def _weather() -> WeatherResponse:
    return WeatherResponse(
        location=WeatherLocation(
            latitude=16.05,
            longitude=108.22,
            timezone="Asia/Ho_Chi_Minh",
        ),
        current=CurrentWeather(
            time="2026-10-18T12:00",
            temperature=30,
            apparent_temperature=34,
            relative_humidity=75,
            is_day=True,
            precipitation=0,
            weather_code=0,
            cloud_cover=10,
            pressure_msl=1012,
            wind_speed=8,
            wind_direction=180,
            wind_gusts=15,
        ),
        hourly=[
            HourlyForecast(
                time="2026-10-19T14:00",
                temperature=29,
                apparent_temperature=32,
                precipitation_probability=20,
                precipitation=0,
                weather_code=1,
                wind_speed=10,
                uv_index=5,
            )
        ],
        forecast=[
            DailyForecast(
                date="2026-10-19",
                temperature_max=31,
                temperature_min=25,
                apparent_temperature_max=34,
                apparent_temperature_min=26,
                sunrise="2026-10-19T05:45",
                sunset="2026-10-19T17:30",
                uv_index_max=8,
                precipitation_sum=1,
                precipitation_probability=30,
                wind_speed_max=15,
                wind_gusts_max=25,
                weather_code=1,
            )
        ],
    )


class TestWeatherContextService(unittest.IsolatedAsyncioTestCase):
    def test_classifies_natural_language_dates_and_time(self) -> None:
        now = datetime(2026, 10, 18, 20, 0, tzinfo=VIETNAM_TZ)
        intent = WeatherContextService.classify(
            "Chiều mai từ 14:00 đến 17:00 đi biển Mỹ Khê có ổn không?",
            now=now,
        )

        self.assertEqual(intent.intent, WeatherIntentType.WEATHER_TIME)
        self.assertEqual(str(intent.start_date), "2026-10-19")
        self.assertEqual(intent.activity, "biển")
        self.assertEqual(intent.start_time.hour, 14)
        self.assertEqual(intent.end_time.hour, 17)

    def test_general_question_does_not_create_weather_intent(self) -> None:
        intent = WeatherContextService.classify("Chùa Linh Ứng có lịch sử như thế nào?")
        self.assertEqual(intent.intent, WeatherIntentType.GENERAL_TRAVEL)

    async def test_context_selects_only_requested_hour(self) -> None:
        intent = WeatherContextService.classify(
            "Chiều mai từ 14:00 đến 17:00 đi biển Mỹ Khê có ổn không?",
            now=datetime(2026, 10, 18, tzinfo=VIETNAM_TZ),
        )
        context = WeatherContextService._select_context(_weather(), intent, "Mỹ Khê")
        self.assertIn("2026-10-19T14:00", context)
        self.assertIn("mưa 20%", context)
        self.assertNotIn("sunrise", context)

    async def test_general_question_does_not_call_weather_api(self) -> None:
        session = MagicMock()
        with patch(
            "app.services.weather_context_service.WeatherService.get_forecast",
            new_callable=AsyncMock,
        ) as get_forecast:
            result = await WeatherContextService.build_context(
                session, "Chùa Linh Ứng có lịch sử như thế nào?"
            )
        self.assertIsNone(result)
        get_forecast.assert_not_awaited()
