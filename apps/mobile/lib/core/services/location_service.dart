import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Normalized permission status across platforms and UI states.
enum LocationPermissionStatus {
  unknown,
  requesting,
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled;

  static LocationPermissionStatus fromGeolocator(
    LocationPermission perm, {
    required bool serviceEnabled,
  }) {
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.unknown;
    }
  }
}

/// Structured result wrapper for location queries.
class LocationResult {
  final Position? position;
  final String? errorMessage;
  final bool isServiceDisabled;
  final bool isPermissionDenied;
  final bool isPermanentlyDenied;
  final bool isTimeout;

  const LocationResult.success(Position this.position)
    : errorMessage = null,
      isServiceDisabled = false,
      isPermissionDenied = false,
      isPermanentlyDenied = false,
      isTimeout = false;

  const LocationResult.failure({
    required this.errorMessage,
    this.isServiceDisabled = false,
    this.isPermissionDenied = false,
    this.isPermanentlyDenied = false,
    this.isTimeout = false,
  }) : position = null;

  bool get hasPosition => position != null;
  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;
  double? get accuracy => position?.accuracy;
}

/// Service handling GPS device checks, permissions, and location acquisition.
class LocationService {
  /// Checks whether GPS / location service is enabled on device or browser.
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Error checking location service status: $e');
      return false;
    }
  }

  /// Checks existing permission without presenting an OS prompt.
  Future<LocationPermission> checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      return LocationPermission.unableToDetermine;
    }
  }

  /// Triggers the OS / browser native permission request dialog.
  Future<LocationPermission> requestPermission() async {
    try {
      return await Geolocator.requestPermission();
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return LocationPermission.unableToDetermine;
    }
  }

  /// Retrieves the user's fresh GPS location with a 15-second timeout.
  /// Requests permission if not yet granted.
  Future<LocationResult> getCurrentPosition() async {
    // 1. Verify location services are active
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationResult.failure(
        errorMessage:
            'Dịch vụ định vị (GPS) đang tắt. Vui lòng bật GPS trên thiết bị.',
        isServiceDisabled: true,
      );
    }

    // 2. Verify permission status (request if denied or unableToDetermine on web)
    LocationPermission permission = await checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      permission = await requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationResult.failure(
        errorMessage: 'Quyền truy cập vị trí bị từ chối.',
        isPermissionDenied: true,
      );
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failure(
        errorMessage:
            'Quyền vị trí bị chặn vĩnh viễn. Vui lòng cấp quyền trong phần Cài đặt.',
        isPermanentlyDenied: true,
      );
    }

    // 3. Query current location with high accuracy & 15-second time limit
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      return LocationResult.success(position);
    } on TimeoutException {
      // Fallback to medium accuracy if high accuracy times out (common on desktop/web)
      try {
        final fallbackPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
        return LocationResult.success(fallbackPos);
      } catch (_) {}

      return const LocationResult.failure(
        errorMessage:
            'Hết thời gian chờ nhận tín hiệu GPS (15s). Vui lòng thử lại.',
        isTimeout: true,
      );
    } on LocationServiceDisabledException {
      return const LocationResult.failure(
        errorMessage: 'Dịch vụ định vị đã bị tắt.',
        isServiceDisabled: true,
      );
    } on PermissionDeniedException {
      return const LocationResult.failure(
        errorMessage: 'Quyền truy cập vị trí đã bị từ chối.',
        isPermissionDenied: true,
      );
    } on PlatformException catch (pe) {
      return LocationResult.failure(
        errorMessage: 'Lỗi hệ thống khi lấy vị trí: ${pe.message ?? pe.code}',
      );
    } catch (e) {
      return LocationResult.failure(
        errorMessage: 'Không thể xác định vị trí hiện tại: $e',
      );
    }
  }

  /// Opens application settings page (supported on Android/iOS).
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }

  /// Opens location service settings page (supported on Android).
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('Error opening location settings: $e');
      return false;
    }
  }
}
