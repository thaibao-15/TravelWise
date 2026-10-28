class CurrentWeather {
  final double temperature;
  final int weatherCode;

  const CurrentWeather({required this.temperature, required this.weatherCode});

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    final temperature = json['temperature'];
    final weatherCode = json['weather_code'];

    if (temperature is! num || weatherCode is! num) {
      throw const FormatException('API trả về dữ liệu thời tiết không hợp lệ');
    }

    return CurrentWeather(
      temperature: temperature.toDouble(),
      weatherCode: weatherCode.toInt(),
    );
  }
}

class WeatherResponse {
  final CurrentWeather current;

  const WeatherResponse({required this.current});

  factory WeatherResponse.fromJson(Map<String, dynamic> json) {
    final current = json['current'];
    if (current is! Map) {
      throw const FormatException('API thiếu dữ liệu thời tiết hiện tại');
    }

    return WeatherResponse(
      current: CurrentWeather.fromJson(Map<String, dynamic>.from(current)),
    );
  }
}
