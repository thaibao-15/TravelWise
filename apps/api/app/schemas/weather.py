from datetime import date

from pydantic import BaseModel, Field


class WeatherLocation(BaseModel):
    latitude: float
    longitude: float
    timezone: str


class CurrentWeather(BaseModel):
    time: str
    temperature: float
    apparent_temperature: float
    relative_humidity: float
    is_day: bool
    precipitation: float
    weather_code: int
    cloud_cover: float
    pressure_msl: float
    wind_speed: float
    wind_direction: float
    wind_gusts: float


class HourlyForecast(BaseModel):
    time: str
    temperature: float
    apparent_temperature: float
    precipitation_probability: float
    precipitation: float
    weather_code: int
    wind_speed: float
    uv_index: float


class DailyForecast(BaseModel):
    date: date
    temperature_max: float
    temperature_min: float
    apparent_temperature_max: float
    apparent_temperature_min: float
    sunrise: str
    sunset: str
    uv_index_max: float
    precipitation_sum: float
    precipitation_probability: float
    wind_speed_max: float
    wind_gusts_max: float
    weather_code: int


class WeatherResponse(BaseModel):
    location: WeatherLocation
    current: CurrentWeather
    hourly: list[HourlyForecast] = Field(min_length=1)
    forecast: list[DailyForecast] = Field(min_length=1)
    source: str = "Open-Meteo"
