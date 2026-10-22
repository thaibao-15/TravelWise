from datetime import date, time
from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class WeatherIntentType(str, Enum):
    GENERAL_TRAVEL = "GENERAL_TRAVEL"
    CURRENT_WEATHER = "CURRENT_WEATHER"
    WEATHER_TODAY = "WEATHER_TODAY"
    WEATHER_TIME = "WEATHER_TIME"
    WEATHER_MULTI_DAY = "WEATHER_MULTI_DAY"
    ACTIVITY_RECOMMENDATION = "ACTIVITY_RECOMMENDATION"
    BEST_DAY_TO_VISIT = "BEST_DAY_TO_VISIT"
    ITINERARY_PLANNING = "ITINERARY_PLANNING"


class WeatherIntent(BaseModel):
    intent: WeatherIntentType = WeatherIntentType.GENERAL_TRAVEL
    destination: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    activity: Optional[str] = None
    user_preferences: list[str] = Field(default_factory=list)

    model_config = ConfigDict(use_enum_values=True)
