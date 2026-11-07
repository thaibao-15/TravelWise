import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Information about a single route leg between two consecutive itinerary stops.
class RouteLegInfo {
  final int fromIndex;
  final int toIndex;
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;

  const RouteLegInfo({
    required this.fromIndex,
    required this.toIndex,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000.0).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final minutes = (durationSeconds / 60.0).ceil();
    if (minutes < 60) {
      return '$minutes phút';
    }
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    if (remainingMins == 0) {
      return '$hours giờ';
    }
    return '$hours giờ $remainingMins phút';
  }
}

/// Result of multi-stop routing containing full polyline and individual legs.
class MultiStopRouteResult {
  final List<LatLng> fullRoute;
  final List<RouteLegInfo> legs;

  const MultiStopRouteResult({
    required this.fullRoute,
    required this.legs,
  });
}

/// Service responsible for fetching driving routes using OSRM.
/// Supports both single-pair routing and multi-stop route calculation with leg breakdown.
class OsrmRoutingService {
  final Dio _dio;
  final Map<String, MultiStopRouteResult> _multiStopCache = {};

  OsrmRoutingService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  /// Calculates a multi-stop road route through all provided [waypoints] in order.
  /// Returns both the continuous fullRoute and separate legs between consecutive stops.
  Future<MultiStopRouteResult> getMultiStopRouteWithLegs(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return MultiStopRouteResult(fullRoute: waypoints, legs: []);
    }

    final cacheKey = waypoints
        .map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join(';');

    if (_multiStopCache.containsKey(cacheKey)) {
      return _multiStopCache[cacheKey]!;
    }

    try {
      final coordsParam = waypoints
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');

      // Request steps or full overview with geometries
      final url =
          'https://router.project-osrm.org/route/v1/driving/$coordsParam?overview=full&geometries=geojson&steps=false';

      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final geometry = route['geometry'] as Map<String, dynamic>?;
          final coords = geometry?['coordinates'] as List<dynamic>?;
          final rawLegs = route['legs'] as List<dynamic>?;

          final decodedFullPoints = <LatLng>[];
          if (coords != null) {
            for (final c in coords) {
              if (c is List && c.length >= 2) {
                decodedFullPoints.add(
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
                );
              }
            }
          }

          final legInfos = <RouteLegInfo>[];

          // If OSRM returns legs
          if (rawLegs != null && rawLegs.isNotEmpty && decodedFullPoints.isNotEmpty) {
            final pointsPerLeg = (decodedFullPoints.length / rawLegs.length).ceil();

            for (int i = 0; i < rawLegs.length; i++) {
              final leg = rawLegs[i] as Map<String, dynamic>;
              final dist = (leg['distance'] as num?)?.toDouble() ?? 0.0;
              final dur = (leg['duration'] as num?)?.toDouble() ?? 0.0;

              final startIdx = (i * pointsPerLeg).clamp(0, decodedFullPoints.length - 1);
              final endIdx = ((i + 1) * pointsPerLeg + 1).clamp(0, decodedFullPoints.length);
              var legSlice = decodedFullPoints.sublist(
                startIdx,
                endIdx > startIdx ? endIdx : (startIdx + 1),
              );

              if (legSlice.isEmpty) {
                legSlice = [waypoints[i], waypoints[i + 1]];
              }

              legInfos.add(
                RouteLegInfo(
                  fromIndex: i,
                  toIndex: i + 1,
                  distanceMeters: dist,
                  durationSeconds: dur,
                  points: legSlice,
                ),
              );
            }
          } else {
            // Generate basic legs between waypoints
            for (int i = 0; i < waypoints.length - 1; i++) {
              legInfos.add(
                RouteLegInfo(
                  fromIndex: i,
                  toIndex: i + 1,
                  distanceMeters: 0,
                  durationSeconds: 0,
                  points: [waypoints[i], waypoints[i + 1]],
                ),
              );
            }
          }

          final result = MultiStopRouteResult(
            fullRoute: decodedFullPoints.length >= 2 ? decodedFullPoints : waypoints,
            legs: legInfos,
          );

          _multiStopCache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('OSRM multi-stop routing error: $e');
    }

    // Fallback: straight lines
    final fallbackLegs = <RouteLegInfo>[];
    for (int i = 0; i < waypoints.length - 1; i++) {
      fallbackLegs.add(
        RouteLegInfo(
          fromIndex: i,
          toIndex: i + 1,
          distanceMeters: 0,
          durationSeconds: 0,
          points: [waypoints[i], waypoints[i + 1]],
        ),
      );
    }
    return MultiStopRouteResult(fullRoute: waypoints, legs: fallbackLegs);
  }

  /// Backward-compatible multi-stop route
  Future<List<LatLng>> getMultiStopRoute(List<LatLng> waypoints) async {
    final result = await getMultiStopRouteWithLegs(waypoints);
    return result.fullRoute;
  }

  /// Calculates route from [from] to [to].
  Future<({double distanceMeters, double durationSeconds, List<LatLng> points})?> getRoute(
    LatLng from,
    LatLng to,
  ) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson';

      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final distanceMeters = (route['distance'] as num).toDouble();
          final durationSeconds = (route['duration'] as num).toDouble();
          final geometry = route['geometry'] as Map<String, dynamic>?;
          final coords = geometry?['coordinates'] as List<dynamic>?;
          final decodedPoints = <LatLng>[];
          if (coords != null) {
            for (final c in coords) {
              if (c is List && c.length >= 2) {
                decodedPoints.add(
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
                );
              }
            }
          }
          return (
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            points: decodedPoints.length >= 2 ? decodedPoints : [from, to],
          );
        }
      }
    } catch (e) {
      debugPrint('OSRM single-leg routing error: $e');
    }
    return null;
  }

  void clearCache() {
    _multiStopCache.clear();
  }

  void dispose() {
    _dio.close();
  }
}
