import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/services/location_service.dart';

/// Presentation state for GPS location and OpenStreetMap interactions.
enum LocationUiStatus { initial, loading, success, error }

class LocationState {
  final LocationUiStatus status;
  final Position? position;
  final LocationPermission permission;
  final bool isServiceDisabled;
  final bool isPermanentlyDenied;
  final String? errorMessage;
  final String? snackMessage;
  final bool cameraNeedsMove;
  final bool hasShownPermissionDialog;

  const LocationState({
    this.status = LocationUiStatus.initial,
    this.position,
    this.permission = LocationPermission.denied,
    this.isServiceDisabled = false,
    this.isPermanentlyDenied = false,
    this.errorMessage,
    this.snackMessage,
    this.cameraNeedsMove = false,
    this.hasShownPermissionDialog = false,
  });

  bool get isLoading => status == LocationUiStatus.loading;
  bool get hasLocation => position != null;
  LatLng? get latLng =>
      position != null ? LatLng(position!.latitude, position!.longitude) : null;
  double? get accuracy => position?.accuracy;

  /// Compatibility getter for widgets expecting LocationPermissionStatus
  LocationPermissionStatus get permissionStatus {
    if (status == LocationUiStatus.loading && position == null) {
      return LocationPermissionStatus.requesting;
    }
    return LocationPermissionStatus.fromGeolocator(
      permission,
      serviceEnabled: !isServiceDisabled,
    );
  }

  LocationState copyWith({
    LocationUiStatus? status,
    Position? position,
    LocationPermission? permission,
    bool? isServiceDisabled,
    bool? isPermanentlyDenied,
    String? errorMessage,
    String? snackMessage,
    bool? cameraNeedsMove,
    bool? hasShownPermissionDialog,
    bool clearSnack = false,
    bool clearError = false,
  }) {
    return LocationState(
      status: status ?? this.status,
      position: position ?? this.position,
      permission: permission ?? this.permission,
      isServiceDisabled: isServiceDisabled ?? this.isServiceDisabled,
      isPermanentlyDenied: isPermanentlyDenied ?? this.isPermanentlyDenied,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      snackMessage: clearSnack ? null : (snackMessage ?? this.snackMessage),
      cameraNeedsMove: cameraNeedsMove ?? this.cameraNeedsMove,
      hasShownPermissionDialog:
          hasShownPermissionDialog ?? this.hasShownPermissionDialog,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _locationService;

  LocationNotifier(this._locationService) : super(const LocationState());

  /// Checks existing permission without asking the OS.
  Future<void> checkInitialStatus() async {
    final perm = await _locationService.checkPermission();
    final disabled = !await _locationService.isLocationServiceEnabled();
    state = state.copyWith(
      permission: perm,
      isServiceDisabled: disabled,
      isPermanentlyDenied: perm == LocationPermission.deniedForever,
    );
  }

  /// Called after user accepts in-app explanation: triggers OS request & fetches position.
  Future<void> requestPermissionAndFetch() async {
    state = state.copyWith(
      status: LocationUiStatus.loading,
      clearError: true,
      clearSnack: true,
    );

    final perm = await _locationService.requestPermission();
    state = state.copyWith(
      permission: perm,
      isPermanentlyDenied: perm == LocationPermission.deniedForever,
    );

    if (perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse) {
      await fetchCurrentLocation();
    } else if (perm == LocationPermission.deniedForever) {
      state = state.copyWith(
        status: LocationUiStatus.error,
        errorMessage:
            'Quyền vị trí bị chặn vĩnh viễn. Vui lòng cấp quyền trong Cài đặt.',
        snackMessage:
            'Vui lòng mở Cài đặt thiết bị để cấp quyền vị trí cho TravelWise.',
      );
    } else {
      state = state.copyWith(
        status: LocationUiStatus.error,
        errorMessage: 'Quyền truy cập vị trí bị từ chối.',
        snackMessage:
            'Bạn chưa cấp quyền vị trí. Nhấn vào biểu tượng vị trí để thử lại.',
      );
    }
  }

  /// Fetches the fresh GPS position with high accuracy.
  Future<void> fetchCurrentLocation() async {
    state = state.copyWith(
      status: LocationUiStatus.loading,
      clearError: true,
      clearSnack: true,
    );

    final result = await _locationService.getCurrentPosition();

    if (result.hasPosition) {
      state = state.copyWith(
        status: LocationUiStatus.success,
        position: result.position,
        cameraNeedsMove: true,
        snackMessage: 'Đã xác định vị trí của bạn thành công!',
      );
    } else {
      state = state.copyWith(
        status: LocationUiStatus.error,
        errorMessage: result.errorMessage ?? 'Không xác định được vị trí.',
        snackMessage: result.errorMessage ?? 'Lỗi xác định vị trí.',
        isServiceDisabled: result.isServiceDisabled,
        isPermanentlyDenied: result.isPermanentlyDenied,
      );
    }
  }

  /// Resets the one-time camera move flag after map camera has adjusted.
  void markCameraMoved() {
    state = state.copyWith(cameraNeedsMove: false);
  }

  /// Clears floating snackbar message once displayed.
  void clearSnack() {
    state = state.copyWith(clearSnack: true);
  }

  /// Opens native app settings.
  Future<bool> openAppSettings() => _locationService.openAppSettings();

  /// Opens native location/GPS settings.
  Future<bool> openLocationSettings() =>
      _locationService.openLocationSettings();

  /// Compatibility method for widgets calling requestLocationPermission()
  Future<void> requestLocationPermission() async {
    state = state.copyWith(hasShownPermissionDialog: true);
    await requestPermissionAndFetch();
  }

  /// Compatibility method for widgets calling skipPermission()
  void skipPermission() {
    state = state.copyWith(hasShownPermissionDialog: true);
  }

  /// Compatibility method for widgets calling relocate()
  Future<void> relocate() async {
    await fetchCurrentLocation();
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final locationProvider = StateNotifierProvider<LocationNotifier, LocationState>(
  (ref) {
    final service = ref.watch(locationServiceProvider);
    return LocationNotifier(service);
  },
);

/// Alias provider for backwards compatibility
final mapProvider = locationProvider;
typedef MapState = LocationState;
typedef MapNotifier = LocationNotifier;
