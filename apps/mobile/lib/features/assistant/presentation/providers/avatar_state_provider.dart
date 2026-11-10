import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Available 3D Avatar models in assets
class Avatar3dOption {
  final String id;
  final String name;
  final String subtitle;
  final String assetPath;
  final String tag;
  final String iconEmoji;

  const Avatar3dOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.assetPath,
    required this.tag,
    this.iconEmoji = '💃',
  });
}

/// Pre-configured 3D avatars available in assets/models
const List<Avatar3dOption> kAvailableAvatars = [
  Avatar3dOption(
    id: 'nam_c',
    name: 'Nam (Anime 3D)',
    subtitle: 'Năng động, lịch lãm, khẩu hình nhép môi 3D chuẩn xác',
    assetPath: 'assets/models/Nam_C.glb',
    tag: 'Khuyên dùng',
    iconEmoji: '🤵',
  ),
  Avatar3dOption(
    id: 'avatar_sample_a',
    name: 'Linh (Anime 3D)',
    subtitle: 'Năng động, cử động nhép môi tự nhiên theo âm thanh',
    assetPath: 'assets/models/AvatarSample_A.glb',
    tag: 'Anime Nữ',
    iconEmoji: '✨',
  ),
];

/// Presentation state for the 3D AI Tour Guide Avatar
class Avatar3dState {
  /// Asset path of the currently selected 3D model
  final String selectedModelPath;

  /// Display name of the loaded 3D model
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
    this.selectedModelPath = 'assets/models/Nam_C.glb',
    this.modelName = 'Nam (Anime 3D)',
    this.isLoading = false,
    this.error,
    this.userOrbitYaw = 0.0,
    this.userOrbitPitch = 0.0,
    this.userZoom = 1.0,
    this.hasMorphTargets = true,
    this.hasSkeleton = true,
  });

  Avatar3dState copyWith({
    String? selectedModelPath,
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
      selectedModelPath: selectedModelPath ?? this.selectedModelPath,
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

  /// Switch the active 3D model asset path
  void selectAvatarModel(String assetPath, {String? modelName}) {
    if (state.selectedModelPath == assetPath && !state.isLoading) return;
    state = state.copyWith(
      selectedModelPath: assetPath,
      modelName: modelName ?? assetPath.split('/').last,
      isLoading: true,
      error: null,
    );
  }

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
    state = state.copyWith(userZoom: zoom.clamp(0.75, 1.85));
  }
}

final avatar3dStateProvider =
    StateNotifierProvider<Avatar3dNotifier, Avatar3dState>((ref) {
  return Avatar3dNotifier();
});
