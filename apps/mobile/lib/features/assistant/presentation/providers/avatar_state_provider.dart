import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presentation state for the 3D AI Tour Guide Avatar
class Avatar3dState {
  /// Name or relative path of the loaded 3D model
  final String modelName;
  final bool isLoading;
  final String? error;

  /// User interactive orbit rotation angles (radians)
  final double userOrbitYaw;
  final double userOrbitPitch;
  final double userZoom;

  /// Whether the 3D model features morph targets (lip-sync blend shapes)
  final bool hasMorphTargets;

  /// Whether the 3D model features a hierarchical skeleton
  final bool hasSkeleton;

  const Avatar3dState({
    this.modelName = 'Linh AI (3D Tour Guide)',
    this.isLoading = false,
    this.error,
    this.userOrbitYaw = 0.0,
    this.userOrbitPitch = 0.0,
    this.userZoom = 1.0,
    this.hasMorphTargets = true,
    this.hasSkeleton = true,
  });

  Avatar3dState copyWith({
    String? modelName,
    bool? isLoading,
    String? error,
    double? userOrbitYaw,
    double? userOrbitPitch,
    double? userZoom,
    bool? hasMorphTargets,
    bool? hasSkeleton,
  }) {
    return Avatar3dState(
      modelName: modelName ?? this.modelName,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userOrbitYaw: userOrbitYaw ?? this.userOrbitYaw,
      userOrbitPitch: userOrbitPitch ?? this.userOrbitPitch,
      userZoom: userZoom ?? this.userZoom,
      hasMorphTargets: hasMorphTargets ?? this.hasMorphTargets,
      hasSkeleton: hasSkeleton ?? this.hasSkeleton,
    );
  }
}

class Avatar3dNotifier extends StateNotifier<Avatar3dState> {
  Avatar3dNotifier() : super(const Avatar3dState());

  void setLoaded({
    required String modelName,
    required bool hasMorphTargets,
    required bool hasSkeleton,
  }) {
    state = state.copyWith(
      modelName: modelName,
      isLoading: false,
      error: null,
      hasMorphTargets: hasMorphTargets,
      hasSkeleton: hasSkeleton,
    );
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setError(String? error) {
    state = state.copyWith(error: error, isLoading: false);
  }

  void addOrbitDelta({required double deltaYaw, required double deltaPitch}) {
    final newYaw = (state.userOrbitYaw + deltaYaw).clamp(-math.pi * 0.45, math.pi * 0.45);
    final newPitch = (state.userOrbitPitch + deltaPitch).clamp(-math.pi * 0.22, math.pi * 0.22);
    state = state.copyWith(userOrbitYaw: newYaw, userOrbitPitch: newPitch);
  }

  void resetOrbit() {
    state = state.copyWith(userOrbitYaw: 0.0, userOrbitPitch: 0.0, userZoom: 1.0);
  }

  void setZoom(double zoom) {
    state = state.copyWith(userZoom: zoom.clamp(0.75, 1.45));
  }
}

final avatar3dStateProvider =
    StateNotifierProvider<Avatar3dNotifier, Avatar3dState>((ref) {
  return Avatar3dNotifier();
});
