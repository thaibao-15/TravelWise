import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/location_provider.dart';
import '../widgets/current_location_marker.dart';
import '../widgets/location_info_card.dart';
import '../widgets/location_permission_dialog.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final MapController _mapController;

  // Default initial center: Hanoi, Vietnam
  static const LatLng _defaultCenter = LatLng(21.0285, 105.8542);
  static const double _defaultZoom = 13.5;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Check existing permissions silently on screen launch (no prompts or GPS activation)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).checkInitialStatus();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ── Location tap action flow ───────────────────────────────────────────────

  Future<void> _handleLocationAction() async {
    final notifier = ref.read(locationProvider.notifier);
    final service = ref.read(locationServiceProvider);

    // 1. Check if location services (GPS) are enabled
    final serviceEnabled = await service.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      await LocationPermissionDialog.showGpsDisabled(
        context,
        onOpenLocationSettings: () => notifier.openLocationSettings(),
      );
      return;
    }

    // 2. Check permission status
    final permission = await service.checkPermission();

    // Permanently denied: guide user to app settings
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await LocationPermissionDialog.showPermanentlyDenied(
        context,
        onOpenSettings: () => notifier.openAppSettings(),
      );
      return;
    }

    // Denied or not determined: show in-app rationale explanation first!
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      if (!mounted) return;
      final userAccepted = await LocationPermissionDialog.show(context);
      if (userAccepted) {
        await notifier.requestPermissionAndFetch();
      }
      return;
    }

    // Permission is already granted (whileInUse or always)
    final currentState = ref.read(locationProvider);
    if (currentState.latLng != null) {
      // Re-center map to current location
      _animateToLocation(currentState.latLng!);
    }
    // Fetch fresh position
    await notifier.fetchCurrentLocation();
  }

  void _animateToLocation(LatLng target) {
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationProvider);

    // Listen to camera move requests when fresh GPS position arrives
    ref.listen<LocationState>(locationProvider, (previous, next) {
      if (next.cameraNeedsMove && next.latLng != null) {
        _animateToLocation(next.latLng!);
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, state),
      body: Stack(
        children: [
          // ── OpenStreetMap ──────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _defaultZoom,
              minZoom: 3.0,
              maxZoom: 19.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // OpenStreetMap Tile Layer with compliant User-Agent
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.travelwise.mobile',
                maxZoom: 19,
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
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      child: const CurrentLocationMarker(),
                    ),
                  ],
                ),

              // OpenStreetMap Attribution
              const SimpleAttributionWidget(
                source: Text('© OpenStreetMap contributors'),
              ),
            ],
          ),

          // ── Loading indicator bar ──────────────────────────────────────────
          if (state.isLoading)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Đang lấy tín hiệu GPS chính xác...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Zoom Controls (+ and -) ────────────────────────────────────────
          Positioned(
            right: AppSpacing.lg,
            top: 20,
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
                ],
              ),
            ),
          ),

          // ── Current Location Floating Action Button ───────────────────────
          Positioned(
            right: AppSpacing.lg,
            bottom: state.hasLocation ? 210 : 32,
            child: _CurrentLocationFab(
              isLoading: state.isLoading,
              hasLocation: state.hasLocation,
              onTap: _handleLocationAction,
            ),
          ),

          // ── Bottom Location Card (Coordinates & Accuracy) ──────────────────
          if (state.hasLocation)
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
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, LocationState state) {
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
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          } else {
            Navigator.maybePop(context);
          }
        },
      ),
      title: const Column(
        children: [
          Text(
            'Bản đồ khám phá',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Khám phá thế giới xung quanh bạn',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
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
