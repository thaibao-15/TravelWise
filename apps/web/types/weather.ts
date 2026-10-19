export interface CurrentWeather {
  time: string;
  temperature: number;
  apparent_temperature: number;
  relative_humidity: number;
  is_day: boolean;
  precipitation: number;
  weather_code: number;
  cloud_cover: number;
  pressure_msl: number;
  wind_speed: number;
  wind_direction: number;
  wind_gusts: number;
}

export interface DailyForecast {
  date: string;
  temperature_max: number;
  temperature_min: number;
  apparent_temperature_max: number;
  apparent_temperature_min: number;
  sunrise: string;
  sunset: string;
  uv_index_max: number;
  precipitation_sum: number;
  precipitation_probability: number;
  wind_speed_max: number;
  wind_gusts_max: number;
  weather_code: number;
}

export interface WeatherResponse {
  location: {
    latitude: number;
    longitude: number;
    timezone: string;
  };
  current: CurrentWeather;
  hourly: Array<{
    time: string;
    temperature: number;
    apparent_temperature: number;
    precipitation_probability: number;
    precipitation: number;
    weather_code: number;
    wind_speed: number;
    uv_index: number;
  }>;
  forecast: DailyForecast[];
  source: string;
}
