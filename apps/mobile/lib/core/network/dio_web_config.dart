import 'package:dio/dio.dart';
import 'package:dio/browser.dart';

/// Configure Dio for Flutter Web: use Fetch API via [BrowserHttpClientAdapter]
/// to avoid XMLHttpRequest CORS issues on long-running requests.
void configurePlatformAdapter(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: false);
}

