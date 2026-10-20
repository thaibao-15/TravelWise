import asyncio
import logging
import re
from datetime import date, datetime, time, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException
from sqlmodel import Session

from app.schemas.trip_planning import CurrentLocation
from app.schemas.weather import WeatherResponse
from app.schemas.weather_intent import WeatherIntent, WeatherIntentType
from app.services.place_service import PlaceService
from app.services.weather_service import WeatherService

logger = logging.getLogger(__name__)

try:
    VIETNAM_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
except ZoneInfoNotFoundError:
    VIETNAM_TZ = timezone(timedelta(hours=7), name="Asia/Ho_Chi_Minh")

_WEATHER_WORDS = (
    "thời tiết",
    "dự báo",
    "mưa",
    "nhiệt độ",
    "nắng",
    "uv",
    "gió",
    "ẩm",
)
_OUTDOOR_ACTIVITIES = ("biển", "tắm biển", "leo núi", "đi bộ", "outdoor", "ngoài trời")


def _number(value: float) -> str:
    return f"{value:g}"


class WeatherContextService:
    @staticmethod
    def classify(question: str, now: Optional[datetime] = None) -> WeatherIntent:
        clean = question.strip()
        lower = clean.lower()
        current_date = (now or datetime.now(VIETNAM_TZ)).date()
        intent = WeatherIntentType.GENERAL_TRAVEL

        has_activity = any(
            phrase in lower
            for phrase in ("có nên", "phù hợp", "đi biển", "tham quan", "leo núi", "hoạt động")
        )
        has_weather = any(word in lower for word in _WEATHER_WORDS) or (
            has_activity and any(word in lower for word in ("ổn", "nên", "phù hợp", "thời tiết"))
        )
        if has_weather:
            if any(phrase in lower for phrase in ("lịch trình", "lên kế hoạch", "tạo lịch")):
                intent = WeatherIntentType.ITINERARY_PLANNING
            elif "ngày nào" in lower or "ngày tốt nhất" in lower or "đẹp nhất" in lower:
                intent = WeatherIntentType.BEST_DAY_TO_VISIT
            elif has_activity:
                intent = WeatherIntentType.ACTIVITY_RECOMMENDATION
            elif _contains_time_range(lower):
                intent = WeatherIntentType.WEATHER_TIME
            elif _contains_multi_day(lower):
                intent = WeatherIntentType.WEATHER_MULTI_DAY
            elif any(word in lower for word in ("hôm nay", "bây giờ", "hiện tại", "lúc này")):
                intent = (
                    WeatherIntentType.WEATHER_TODAY
                    if "hôm nay" in lower
                    else WeatherIntentType.CURRENT_WEATHER
                )
            else:
                intent = WeatherIntentType.CURRENT_WEATHER

        start_date, end_date = _extract_dates(lower, current_date)
        start_time, end_time = _extract_times(lower)
        if start_date and end_date and start_date != end_date and intent == WeatherIntentType.CURRENT_WEATHER:
            intent = WeatherIntentType.WEATHER_MULTI_DAY
        if start_time and intent in {
            WeatherIntentType.WEATHER_TODAY,
            WeatherIntentType.CURRENT_WEATHER,
            WeatherIntentType.ACTIVITY_RECOMMENDATION,
        }:
            intent = WeatherIntentType.WEATHER_TIME

        destination = _extract_destination(clean)
        activity = _extract_activity(lower)
        preferences = [activity] if activity else []
        return WeatherIntent(
            intent=intent,
            destination=destination,
            start_date=start_date,
            end_date=end_date,
            start_time=start_time,
            end_time=end_time,
            activity=activity,
            user_preferences=preferences,
        )

    @classmethod
    async def build_context(
        cls,
        session: Session,
        question: str,
        current_location: Optional[CurrentLocation] = None,
    ) -> Optional[str]:
        intent = cls.classify(question)
        if intent.intent == WeatherIntentType.GENERAL_TRAVEL:
            return None

        coordinates = None
        destination = intent.destination
        if current_location:
            coordinates = (current_location.latitude, current_location.longitude)
        elif destination:
            places = PlaceService.search_places_by_keyword(session, destination, limit=5)
            place = next(
                (item for item in places if item.latitude is not None and item.longitude is not None),
                None,
            )
            if place:
                coordinates = (place.latitude, place.longitude)
                destination = place.name

        if coordinates is None:
            return (
                "=== THỜI TIẾT ===\n"
                "Không xác định được tọa độ hợp lệ cho địa điểm thời tiết; "
                "không được suy đoán số liệu thời tiết."
            )

        forecast_days = _forecast_days(intent)
        try:
            weather = await WeatherService.get_forecast(
                coordinates[0], coordinates[1], forecast_days
            )
        except HTTPException as exc:
            logger.warning("Weather context unavailable: %s", exc.detail)
            return (
                "=== THỜI TIẾT ===\n"
                "Không thể xác minh dữ liệu thời tiết lúc này. "
                "Hãy nói rõ giới hạn này thay vì tự tạo số liệu."
            )
        except Exception:
            logger.exception("Unexpected weather context failure")
            return (
                "=== THỜI TIẾT ===\n"
                "Không thể xác minh dữ liệu thời tiết lúc này. "
                "Hãy nói rõ giới hạn này thay vì tự tạo số liệu."
            )
        return cls._select_context(weather, intent, destination)

    @staticmethod
    def build_context_sync(
        session: Session,
        question: str,
        current_location: Optional[CurrentLocation] = None,
    ) -> Optional[str]:
        return asyncio.run(
            WeatherContextService.build_context(session, question, current_location)
        )

    @staticmethod
    def _select_context(
        weather: WeatherResponse,
        intent: WeatherIntent,
        destination: Optional[str],
    ) -> str:
        header = f"=== THỜI TIẾT CÓ CẤU TRÚC ({intent.intent}) ===\n"
        lines = [
            header,
            f"Địa điểm: {destination or 'tọa độ đã xác nhận'}",
            f"Múi giờ: {weather.location.timezone}",
        ]
        if intent.intent == WeatherIntentType.CURRENT_WEATHER:
            current = weather.current
            lines.append(
                "Hiện tại: "
                f"nhiệt độ {_number(current.temperature)}°C, "
                f"cảm nhận {_number(current.apparent_temperature)}°C, "
                f"độ ẩm {_number(current.relative_humidity)}%, mã thời tiết {current.weather_code}, "
                f"gió {_number(current.wind_speed)} km/h, mưa {_number(current.precipitation)} mm."
            )
            return "\n".join(lines)

        if intent.intent in {
            WeatherIntentType.WEATHER_TODAY,
            WeatherIntentType.WEATHER_TIME,
            WeatherIntentType.ACTIVITY_RECOMMENDATION,
        }:
            current = weather.current
            lines.append(
                f"Hiện tại: {_number(current.temperature)}°C, "
                f"cảm nhận {_number(current.apparent_temperature)}°C, "
                f"mã thời tiết {current.weather_code}."
            )
            hourly = weather.hourly
            if intent.start_date:
                hourly = [item for item in hourly if item.time.startswith(str(intent.start_date))]
            if intent.start_time:
                hourly = [
                    item
                    for item in hourly
                    if _time_in_range(item.time, intent.start_time, intent.end_time)
                ]
            for item in hourly[:24]:
                lines.append(
                    f"Giờ {item.time}: {_number(item.temperature)}°C, "
                    f"mưa {_number(item.precipitation_probability)}%, "
                    f"lượng mưa {_number(item.precipitation)} mm, mã {item.weather_code}, "
                    f"gió {_number(item.wind_speed)} km/h, UV {_number(item.uv_index)}."
                )
            return "\n".join(lines)

        selected = weather.forecast
        if intent.start_date:
            end_date = intent.end_date or intent.start_date
            selected = [
                item for item in selected if intent.start_date <= item.date <= end_date
            ]
        for item in selected:
            lines.append(
                f"Ngày {item.date}: {_number(item.temperature_min)}-{_number(item.temperature_max)}°C, "
                f"cảm nhận {_number(item.apparent_temperature_min)}-{_number(item.apparent_temperature_max)}°C, "
                f"mưa {_number(item.precipitation_probability)}%, "
                f"tổng {_number(item.precipitation_sum)} mm, "
                f"mã {item.weather_code}, UV {_number(item.uv_index_max)}, "
                f"bình minh {item.sunrise}, hoàng hôn {item.sunset}."
            )
        return "\n".join(lines)


def _contains_multi_day(text: str) -> bool:
    return any(phrase in text for phrase in ("ba ngày", "3 ngày", "nhiều ngày", "tuần tới", "cuối tuần"))


def _contains_time_range(text: str) -> bool:
    return bool(re.search(r"\b\d{1,2}(?:[:h]\d{0,2})?\s*(?:-|đến|tới)\s*\d{1,2}", text))


def _extract_dates(text: str, current_date: date) -> tuple[Optional[date], Optional[date]]:
    if "hôm nay" in text:
        return current_date, current_date
    if "ngày mai" in text or "mai" in text:
        tomorrow = current_date + timedelta(days=1)
        return tomorrow, tomorrow
    if "ba ngày tới" in text or "3 ngày tới" in text:
        return current_date, current_date + timedelta(days=2)
    if "cuối tuần này" in text:
        days_until_saturday = (5 - current_date.weekday()) % 7
        saturday = current_date + timedelta(days=days_until_saturday)
        return saturday, saturday + timedelta(days=1)
    return None, None


def _extract_times(text: str) -> tuple[Optional[time], Optional[time]]:
    match = re.search(
        r"(\d{1,2})(?::(\d{2}))?\s*(?:giờ|h)?\s*(?:-|đến|tới)\s*"
        r"(\d{1,2})(?::(\d{2}))?",
        text,
    )
    if not match:
        return None, None
    start = time(int(match.group(1)), int(match.group(2) or 0))
    end = time(int(match.group(3)), int(match.group(4) or 0))
    return start, end


def _extract_destination(question: str) -> Optional[str]:
    match = re.search(
        r"(?:ở|tại|đến|đi|tham quan)\s+([^?.!,]+?)(?=\s+(?:hôm nay|ngày mai|mai|ba ngày|3 ngày|có|thì|không|đẹp|thế nào)|[?.!,]|$)",
        question,
        flags=re.IGNORECASE,
    )
    if match:
        return match.group(1).strip()

    candidate = re.sub(r"^(?:cho tôi biết\s+)?(?:thời tiết|dự báo)\s+", "", question, flags=re.I)
    candidate = re.split(
        r"\s+(?:hôm nay|ngày mai|mai|ba ngày tới|3 ngày tới|tuần tới|hiện tại|bây giờ|thế nào)\b",
        candidate,
        maxsplit=1,
        flags=re.I,
    )[0]
    candidate = re.sub(r"\s+(?:có|sẽ|như thế nào)\s*$", "", candidate, flags=re.I).strip(" ?.!,")
    return candidate or None


def _extract_activity(text: str) -> Optional[str]:
    for activity in _OUTDOOR_ACTIVITIES:
        if activity in text:
            return activity
    return None


def _forecast_days(intent: WeatherIntent) -> int:
    if intent.start_date and intent.end_date:
        return min(16, max(1, (intent.end_date - intent.start_date).days + 1))
    if intent.intent in {
        WeatherIntentType.WEATHER_MULTI_DAY,
        WeatherIntentType.BEST_DAY_TO_VISIT,
        WeatherIntentType.ITINERARY_PLANNING,
    }:
        return 7
    return 1 if intent.intent in {WeatherIntentType.CURRENT_WEATHER, WeatherIntentType.WEATHER_TODAY} else 7


def _time_in_range(value: str, start: time, end: Optional[time]) -> bool:
    current = datetime.fromisoformat(value).time()
    return start <= current <= (end or start)
