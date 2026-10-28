import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../shared/widgets/bottom_nav_bar.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../../../trips/models/trip_model.dart';
import '../providers/location_provider.dart';
import '../widgets/current_location_marker.dart';
import '../widgets/location_info_card.dart';
import '../widgets/location_permission_dialog.dart';

class _RouteEstimate {
  final double distanceKm;
  final int durationMinutes;
  final List<LatLng> routePoints;
  final bool isRoadRoute;

  const _RouteEstimate({
    required this.distanceKm,
    required this.durationMinutes,
    required this.routePoints,
    this.isRoadRoute = false,
  });

  String get formattedDistance {
    if (distanceKm < 1.0) {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    if (durationMinutes < 1) return 'Dưới 1 phút';
    if (durationMinutes < 60) return '$durationMinutes phút';
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    if (mins == 0) return '$hours giờ';
    return '$hours giờ $mins phút';
  }
}

class MapScreen extends ConsumerStatefulWidget {
  final Trip? trip;
  final int? initialDayIndex;
  final int? originatingTabIndex;
  final ItineraryActivity? initialSelectedActivity;

  const MapScreen({
    super.key,
    this.trip,
    this.initialDayIndex,
    this.originatingTabIndex,
    this.initialSelectedActivity,
  });

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final MapController _mapController;
  final Dio _osrmDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  // Default initial center: Hanoi, Vietnam
  static const LatLng _defaultCenter = LatLng(21.0285, 105.8542);
  static const double _defaultZoom = 13.5;

  int _selectedDayFilter = 0; // 0 = All days, 1 = Day 1, etc.
  ItineraryActivity? _selectedActivity;
  _RouteEstimate? _routeEstimate;
  bool _isCalculatingRoute = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedDayFilter = widget.initialDayIndex ?? 0;
    _selectedActivity = widget.initialSelectedActivity;

    // Check existing permissions silently on screen launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(locationProvider.notifier).checkInitialStatus();
      if (_selectedActivity != null && _selectedActivity!.hasValidCoordinates) {
        _selectActivity(_selectedActivity!, showBanner: true);
      } else if (widget.trip != null) {
        _fitItineraryCamera();
      }
    });
  }

  @override
  void dispose() {
    _osrmDio.close();
    _mapController.dispose();
    super.dispose();
  }

  // ── Navigation Helpers ────────────────────────────────────────────────────

  void _handleBackNavigation(BuildContext context, int fallbackTabIndex) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (MainShell.currentTab != -1) {
      MainShell.switchToTab(context, fallbackTabIndex);
    }
  }

  void _handleBottomNavTap(BuildContext context, int index) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    MainShell.switchToTab(context, index);
  }

  // ── Color coding per day ──────────────────────────────────────────────────

  Color _getDayColor(int dayIndex) {
    switch (dayIndex % 6) {
      case 1:
        return const Color(0xFF2563EB); // Royal Blue
      case 2:
        return const Color(0xFF059669); // Emerald Green
      case 3:
        return const Color(0xFFD97706); // Amber
      case 4:
        return const Color(0xFF7C3AED); // Purple
      case 5:
        return const Color(0xFFDB2777); // Pink
      default:
        return const Color(0xFF4B5563); // Gray
    }
  }

  // ── Location tap action flow ───────────────────────────────────────────────

  Future<void> _handleLocationAction() async {
    final notifier = ref.read(locationProvider.notifier);
    final service = ref.read(locationServiceProvider);

    final serviceEnabled = await service.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      await LocationPermissionDialog.showGpsDisabled(
        context,
        onOpenLocationSettings: () => notifier.openLocationSettings(),
      );
      return;
    }

    final permission = await service.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await LocationPermissionDialog.showPermanentlyDenied(
        context,
        onOpenSettings: () => notifier.openAppSettings(),
      );
      return;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      if (!mounted) return;
      final userAccepted = await LocationPermissionDialog.show(context);
      if (userAccepted) {
        await notifier.requestPermissionAndFetch();
        if (mounted && _selectedActivity != null) {
          final updatedPos = ref.read(locationProvider).latLng;
          if (updatedPos != null) {
            await _calculateRouteToActivity(
              updatedPos,
              _selectedActivity!,
              showBanner: true,
            );
          }
        }
      }
      return;
    }

    final currentState = ref.read(locationProvider);
    if (currentState.latLng != null && _selectedActivity == null) {
      _animateToLocation(currentState.latLng!);
    }
    await notifier.fetchCurrentLocation();
    if (mounted && _selectedActivity != null) {
      final updatedPos = ref.read(locationProvider).latLng;
      if (updatedPos != null) {
        await _calculateRouteToActivity(
          updatedPos,
          _selectedActivity!,
          showBanner: true,
        );
      }
    }
  }

  void _animateToLocation(LatLng target) {
    if (!mounted) return;
    try {
      _mapController.move(target, 16.0);
    } catch (e) {
      debugPrint('Error moving map camera: $e');
    }
  }

  void _zoomIn() {
    try {
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_mapController.camera.center, currentZoom + 1.0);
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_mapController.camera.center, currentZoom - 1.0);
    } catch (_) {}
  }

  // ── Route Calculation & Activity Selection ─────────────────────────────────

  _RouteEstimate _computeFallbackEstimate(LatLng from, LatLng to) {
    final straightMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    // Approximate road distance (~1.3x straight line)
    final estimatedKm = (straightMeters / 1000.0) * 1.3;
    // Average travel speed (~35 km/h in city, ~55 km/h for longer intercity routes)
    final avgSpeedKmh = estimatedKm > 30 ? 55.0 : 35.0;
    final minutes = ((estimatedKm / avgSpeedKmh) * 60).ceil().clamp(1, 99999);

    return _RouteEstimate(
      distanceKm: estimatedKm,
      durationMinutes: minutes,
      routePoints: [from, to],
      isRoadRoute: false,
    );
  }

  Future<void> _selectActivity(
    ItineraryActivity act, {
    bool showBanner = true,
  }) async {
    setState(() {
      _selectedActivity = act;
    });

    if (!act.hasValidCoordinates) return;

    final dest = LatLng(act.latitude!, act.longitude!);
    var userLatLng = ref.read(locationProvider).latLng;

    if (userLatLng != null) {
      await _calculateRouteToActivity(
        userLatLng,
        act,
        showBanner: showBanner,
      );
    } else {
      try {
        _mapController.move(dest, 15.5);
      } catch (_) {}
      // Prompt or auto-fetch user location so we can display distance & duration
      final service = ref.read(locationServiceProvider);
      final perm = await service.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        await ref
            .read(locationProvider.notifier)
            .fetchCurrentLocation(silentCamera: true);
        userLatLng = ref.read(locationProvider).latLng;
        if (mounted && userLatLng != null && _selectedActivity?.id == act.id) {
          await _calculateRouteToActivity(
            userLatLng,
            act,
            showBanner: showBanner,
          );
        }
      }
    }
  }

  Future<void> _calculateRouteToActivity(
    LatLng from,
    ItineraryActivity act, {
    bool showBanner = true,
  }) async {
    if (!act.hasValidCoordinates) return;
    final to = LatLng(act.latitude!, act.longitude!);

    // Immediate instant estimate so UI responds right away
    final fallback = _computeFallbackEstimate(from, to);
    setState(() {
      _routeEstimate = fallback;
      _isCalculatingRoute = true;
    });

    _fitPointsCamera([from, to]);

    // Query OSRM public driving route API for real road distance, duration & geometry
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson';

      final response = await _osrmDio.get(url);
      if (!mounted || _selectedActivity?.id != act.id) return;

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

          final roadEstimate = _RouteEstimate(
            distanceKm: distanceMeters / 1000.0,
            durationMinutes: (durationSeconds / 60.0).ceil().clamp(1, 99999),
            routePoints: decodedPoints.length >= 2 ? decodedPoints : [from, to],
            isRoadRoute: true,
          );

          setState(() {
            _routeEstimate = roadEstimate;
            _isCalculatingRoute = false;
          });

          if (showBanner) {
            _showRouteSnackNotification(act, roadEstimate);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fallback used: $e');
    }

    if (!mounted || _selectedActivity?.id != act.id) return;
    setState(() {
      _isCalculatingRoute = false;
    });

    if (showBanner && _routeEstimate != null) {
      _showRouteSnackNotification(act, _routeEstimate!);
    }
  }

  void _showRouteSnackNotification(
    ItineraryActivity act,
    _RouteEstimate estimate,
  ) {
    if (!mounted) return;
    final placeTitle = act.placeName ?? act.title;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.dark,
        elevation: 8,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 195),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đến $placeTitle',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Khoảng cách: ${estimate.formattedDistance} • Thời gian: ~${estimate.formattedDuration}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fitPointsCamera(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      try {
        _mapController.move(points.first, 15.0);
      } catch (_) {}
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
      try {
        _mapController.move(points.first, 15.5);
      } catch (_) {}
      return;
    }

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            left: 54,
            right: 54,
            top: 100,
            bottom: 220,
          ),
        ),
      );
    } catch (_) {
      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      try {
        _mapController.move(center, 13.0);
      } catch (_) {}
    }
  }

  // ── Itinerary Points & Camera Fitting ──────────────────────────────────────

  List<({TripDay day, ItineraryActivity activity})> _getFilteredItineraryItems() {
    if (widget.trip == null) return [];
    final items = <({TripDay day, ItineraryActivity activity})>[];

    for (final day in widget.trip!.days) {
      if (_selectedDayFilter != 0 && day.dayIndex != _selectedDayFilter) {
        continue;
      }
      for (final act in day.activities) {
        if (act.hasValidCoordinates) {
          items.add((day: day, activity: act));
        }
      }
    }
    return items;
  }

  void _fitItineraryCamera() {
    final items = _getFilteredItineraryItems();
    if (items.isEmpty) return;

    final points = items
        .map((i) => LatLng(i.activity.latitude!, i.activity.longitude!))
        .toList();

    final userLatLng = ref.read(locationProvider).latLng;
    if (userLatLng != null) {
      points.add(userLatLng);
    }

    _fitPointsCamera(points);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationProvider);

    // Listen to camera move requests when fresh GPS position arrives
    ref.listen<LocationState>(locationProvider, (previous, next) {
      if (next.latLng != null &&
          previous?.latLng != next.latLng &&
          _selectedActivity != null) {
        _calculateRouteToActivity(
          next.latLng!,
          _selectedActivity!,
          showBanner: true,
        );
      } else if (next.cameraNeedsMove && next.latLng != null) {
        if (widget.trip != null && _selectedActivity == null) {
          _fitItineraryCamera();
        } else {
          _animateToLocation(next.latLng!);
        }
        ref.read(locationProvider.notifier).markCameraMoved();
      }

      if (next.snackMessage != null &&
          next.snackMessage != previous?.snackMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.snackMessage!),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(AppSpacing.lg),
            backgroundColor: next.status == LocationUiStatus.error
                ? AppColors.error
                : AppColors.dark,
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(locationProvider.notifier).clearSnack();
      }
    });

    final currentPosition = state.latLng;
    final accuracy = state.accuracy;

    final itineraryItems = _getFilteredItineraryItems();
    final polylinePoints = itineraryItems
        .map((i) => LatLng(i.activity.latitude!, i.activity.longitude!))
        .toList();

    int activeBottomNavIndex = widget.originatingTabIndex ??
        (MainShell.currentTab >= 0 ? MainShell.currentTab : 0);
    if (activeBottomNavIndex < 0 || activeBottomNavIndex > 4) {
      activeBottomNavIndex = 0;
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation(context, activeBottomNavIndex);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context, state, activeBottomNavIndex),
        body: Stack(
          children: [
            // ── Map Layer ──────────────────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: itineraryItems.isNotEmpty
                    ? LatLng(
                        itineraryItems.first.activity.latitude!,
                        itineraryItems.first.activity.longitude!,
                      )
                    : _defaultCenter,
                initialZoom: itineraryItems.isNotEmpty ? 13.0 : _defaultZoom,
                minZoom: 3.0,
                maxZoom: 19.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (_, __) {
                  if (_selectedActivity != null) {
                    setState(() {
                      _selectedActivity = null;
                      _routeEstimate = null;
                    });
                  }
                },
              ),
              children: [
                // ArcGIS / OpenStreetMap Tile Layer
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/'
                      'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                  maxNativeZoom: 19,
                ),

                // Sovereignty Markers (Hoàng Sa & Trường Sa)
                const MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(16.5, 112.0),
                      width: 190,
                      height: 45,
                      child: Text(
                        'Quần đảo Hoàng Sa (Việt Nam)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          shadows: [
                            Shadow(
                              color: Colors.white,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Marker(
                      point: LatLng(10.0, 114.0),
                      width: 190,
                      height: 45,
                      child: Text(
                        'Quần đảo Trường Sa (Việt Nam)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          shadows: [
                            Shadow(
                              color: Colors.white,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Route Preview Polyline (Ordered itinerary stops)
                if (polylinePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: polylinePoints,
                        strokeWidth: 3.5,
                        color: _getDayColor(
                          _selectedDayFilter > 0 ? _selectedDayFilter : 1,
                        ).withOpacity(0.65),
                      ),
                    ],
                  ),

                // Active Route Line from User Current Location to Selected Activity
                if (currentPosition != null &&
                    _selectedActivity != null &&
                    _routeEstimate != null &&
                    _routeEstimate!.routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routeEstimate!.routePoints,
                        strokeWidth: 5.0,
                        color: const Color(0xFF0EA5E9),
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),

                // GPS Accuracy Circle
                if (currentPosition != null && accuracy != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: currentPosition,
                        radius: accuracy.clamp(12.0, 300.0),
                        useRadiusInMeter: true,
                        color: AppColors.primary.withOpacity(0.12),
                        borderColor: AppColors.primary.withOpacity(0.35),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),

                // User Current Location Marker
                if (currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: currentPosition,
                        width: 110,
                        height: 68,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Vị trí của bạn',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const CurrentLocationMarker(size: 38),
                          ],
                        ),
                      ),
                    ],
                  ),

                // Itinerary Activity Markers
                if (itineraryItems.isNotEmpty)
                  MarkerLayer(
                    markers: itineraryItems.map((item) {
                      final isSelected =
                          _selectedActivity?.id == item.activity.id;
                      final color = _getDayColor(item.day.dayIndex);

                      return Marker(
                        point: LatLng(
                          item.activity.latitude!,
                          item.activity.longitude!,
                        ),
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () => _selectActivity(
                            item.activity,
                            showBanner: true,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: isSelected ? 44 : 38,
                            height: isSelected ? 44 : 38,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.dark : color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: isSelected ? 3.0 : 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.28),
                                  blurRadius: isSelected ? 12 : 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '${item.activity.activityOrder ?? 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                // Attribution
                SimpleAttributionWidget(
                  source: const Text(
                    '© OpenStreetMap',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),

            // ── Day Filter Bar (If trip is provided) ──────────────────────────
            if (widget.trip != null && widget.trip!.days.isNotEmpty)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _buildDayFilterBar(),
              ),

            // ── Zoom Controls (+ and -) ────────────────────────────────────────
            Positioned(
              right: AppSpacing.lg,
              top: widget.trip != null ? 72 : 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.add_rounded,
                        color: AppColors.textPrimary,
                      ),
                      tooltip: 'Phóng to',
                      onPressed: _zoomIn,
                    ),
                    Container(width: 32, height: 1, color: AppColors.border),
                    IconButton(
                      icon: const Icon(
                        Icons.remove_rounded,
                        color: AppColors.textPrimary,
                      ),
                      tooltip: 'Thu nhỏ',
                      onPressed: _zoomOut,
                    ),
                    if (widget.trip != null) ...[
                      Container(width: 32, height: 1, color: AppColors.border),
                      IconButton(
                        icon: const Icon(
                          Icons.crop_free_rounded,
                          color: AppColors.primary,
                        ),
                        tooltip: 'Xem trọn lộ trình',
                        onPressed: _fitItineraryCamera,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Current Location Floating Action Button ───────────────────────
            Positioned(
              right: AppSpacing.lg,
              bottom: _selectedActivity != null
                  ? 220
                  : (state.hasLocation && widget.trip == null ? 210 : 32),
              child: _CurrentLocationFab(
                isLoading: state.isLoading,
                hasLocation: state.hasLocation,
                onTap: _handleLocationAction,
              ),
            ),

            // ── Selected Marker Activity Card ────────────────────────────────
            if (_selectedActivity != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: _buildSelectedActivityCard(_selectedActivity!, state),
              )
            else if (state.hasLocation && widget.trip == null)
              // Bottom GPS info card (shown on standalone Explore map)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: LocationInfoCard(
                    onUpdateLocation: _handleLocationAction,
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: CustomBottomNavBar(
          currentIndex: activeBottomNavIndex,
          onTap: (index) => _handleBottomNavTap(context, index),
        ),
      ),
    );
  }

  Widget _buildDayFilterBar() {
    final days = widget.trip!.days;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDayFilterPill(
              label: 'Tất cả (${itineraryCount(0)})',
              isSelected: _selectedDayFilter == 0,
              color: AppColors.primary,
              onTap: () {
                setState(() => _selectedDayFilter = 0);
                _fitItineraryCamera();
              },
            ),
            const SizedBox(width: 6),
            ...days.map((d) {
              final count = itineraryCount(d.dayIndex);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildDayFilterPill(
                  label: 'Ngày ${d.dayIndex} ($count)',
                  isSelected: _selectedDayFilter == d.dayIndex,
                  color: _getDayColor(d.dayIndex),
                  onTap: () {
                    setState(() => _selectedDayFilter = d.dayIndex);
                    _fitItineraryCamera();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  int itineraryCount(int dayIndex) {
    if (widget.trip == null) return 0;
    int count = 0;
    for (final d in widget.trip!.days) {
      if (dayIndex == 0 || d.dayIndex == dayIndex) {
        count += d.activities.where((a) => a.hasValidCoordinates).length;
      }
    }
    return count;
  }

  Widget _buildDayFilterPill({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedActivityCard(
    ItineraryActivity act,
    LocationState locationState,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${act.activityOrder ?? 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      act.placeName ?? act.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (act.startTime.isNotEmpty) ...[
                          Text(
                            '${act.startTime} - ${act.endTime}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '•',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            act.category,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => setState(() {
                  _selectedActivity = null;
                  _routeEstimate = null;
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          // ── Distance & Travel Time Info Banner from Current Location ─────
          const SizedBox(height: 12),
          if (locationState.hasLocation && _routeEstimate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.1),
                    const Color(0xFF0EA5E9).withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.navigation,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Cách vị trí của bạn ${_routeEstimate!.formattedDistance}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            if (_isCalculatingRoute) ...[
                              const SizedBox(width: 6),
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Dự kiến di chuyển: ~${_routeEstimate!.formattedDuration} (${_routeEstimate!.isRoadRoute ? 'theo đường bộ' : 'ước tính'})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: locationState.isLoading ? null : _handleLocationAction,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: locationState.isLoading
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        locationState.isLoading
                            ? 'Đang lấy vị trí của bạn để tính quãng đường...'
                            : 'Bấm để bật vị trí của bạn & xem quãng đường, thời gian đến đây',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),

          if (act.placeAddress != null && act.placeAddress!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    act.placeAddress!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (act.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              act.description,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    LocationState state,
    int fallbackTabIndex,
  ) {
    final title = widget.trip != null
        ? widget.trip!.title
        : 'Bản đồ khám phá';
    final subtitle = widget.trip != null
        ? '${widget.trip!.destination} · ${_getFilteredItineraryItems().length} điểm dừng'
        : 'Khám phá thế giới xung quanh bạn';

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 16,
          ),
        ),
        tooltip: 'Quay lại',
        onPressed: () => _handleBackNavigation(context, fallbackTabIndex),
      ),
      title: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: 'Vị trí của tôi',
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: state.hasLocation
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              Icons.my_location_rounded,
              color: state.hasLocation
                  ? AppColors.primary
                  : AppColors.textSecondary,
              size: 16,
            ),
          ),
          onPressed: state.isLoading ? null : _handleLocationAction,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }
}

// ── Floating Action Button for Current Location ───────────────────────────────

class _CurrentLocationFab extends StatelessWidget {
  final bool isLoading;
  final bool hasLocation;
  final VoidCallback onTap;

  const _CurrentLocationFab({
    required this.isLoading,
    required this.hasLocation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Vị trí của tôi',
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: hasLocation ? AppColors.primary : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (hasLocation ? AppColors.primary : Colors.black)
                    .withOpacity(0.2),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: hasLocation ? Colors.transparent : AppColors.border,
            ),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(
                        hasLocation ? Colors.white : AppColors.primary,
                      ),
                    ),
                  )
                : Icon(
                    Icons.my_location_rounded,
                    color: hasLocation ? Colors.white : AppColors.primary,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}
