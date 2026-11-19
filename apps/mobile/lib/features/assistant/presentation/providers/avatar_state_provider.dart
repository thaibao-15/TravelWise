import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supported visual display modes for the AI Tour Guide Avatar
enum AvatarDisplayMode {
  /// 2D Realistic Talking Photo (`assets/images/hdv.png`) with 60fps GPU mesh deformation & lip-sync
  photo2d,

  /// 3D glTF / VRM animated humanoid character (`Nam_C.glb`, `AvatarSample_A.glb`)
  model3d,
}

/// Available 2D Photo Avatars in assets/images
class AvatarPhotoOption {
  final String id;
  final String name;
  final String subtitle;
  final String assetPath;
  final String gender; // 'female' or 'male'
  final String tag;
  final String iconEmoji;

  const AvatarPhotoOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.assetPath,
    required this.gender,
    required this.tag,
    this.iconEmoji = '👩',
  });
}

const List<AvatarPhotoOption> kAvailablePhotos = [
  AvatarPhotoOption(
    id: 'hdv_nu',
    name: 'Linh (HDV Nữ Thực tế)',
    subtitle: 'Tươi tắn, truyền cảm, phong thái hướng dẫn viên chuyên nghiệp',
    assetPath: 'assets/images/hdv.png',
    gender: 'female',
    tag: 'Mặc định',
    iconEmoji: '👩',
  ),
  AvatarPhotoOption(
    id: 'hdv_nam',
    name: 'Nam (HDV Nam Thực tế)',
    subtitle: 'Lịch thiệp, ấm áp, phong thái hướng dẫn viên du lịch năng động',
    assetPath: 'assets/images/hdvNam.png',
    gender: 'male',
    tag: 'Mới',
    iconEmoji: '👨',
  ),
];

/// Available 3D Avatar models in assets
class Avatar3dOption {
  final String id;
  final String name;
  final String subtitle;
  final String assetPath;
  final String gender; // 'male' or 'female'
  final String tag;
  final String iconEmoji;

  const Avatar3dOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.assetPath,
    this.gender = 'female',
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
    gender: 'male',
    tag: 'Khuyên dùng',
    iconEmoji: '🤵',
  ),
  Avatar3dOption(
    id: 'avatar_sample_a',
    name: 'Linh (Anime 3D)',
    subtitle: 'Năng động, cử động nhép môi tự nhiên theo âm thanh',
    assetPath: 'assets/models/AvatarSample_A.glb',
    gender: 'female',
    tag: 'Anime Nữ',
    iconEmoji: '✨',
  ),
];

/// Presentation state for the AI Tour Guide Avatar (supports both 2D Photo & 3D Model)
class Avatar3dState {
  /// Active visual display mode (2D Talking Photo or 3D Model)
  final AvatarDisplayMode displayMode;

  /// Asset path of the currently selected 2D photo
  final String selectedPhotoPath;

  /// Display name of the active 2D photo
  final String photoName;

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
    this.displayMode = AvatarDisplayMode.photo2d,
    this.selectedPhotoPath = 'assets/images/hdv.png',
    this.photoName = 'Linh (HDV Nữ Thực tế)',
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

  bool get is2dMode => displayMode == AvatarDisplayMode.photo2d;
  bool get is3dMode => displayMode == AvatarDisplayMode.model3d;

  /// Returns 'Nam' or 'Nữ' based on currently displayed avatar character
  String get currentGender {
    if (is2dMode) {
      return selectedPhotoPath.contains('Nam') ? 'Nam' : 'Nữ';
    } else {
      return selectedModelPath.contains('Nam') ? 'Nam' : 'Nữ';
    }
  }

  Avatar3dState copyWith({
    AvatarDisplayMode? displayMode,
    String? selectedPhotoPath,
    String? photoName,
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
      displayMode: displayMode ?? this.displayMode,
      selectedPhotoPath: selectedPhotoPath ?? this.selectedPhotoPath,
      photoName: photoName ?? this.photoName,
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
  static const String _storageKeyMode = 'avatar_display_mode';
  static const String _storageKeyPhoto = 'avatar_selected_photo';
  final FlutterSecureStorage _storage;

  Avatar3dNotifier({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        super(const Avatar3dState()) {
    _loadSavedMode();
  }

  Future<void> _loadSavedMode() async {
    try {
      final savedMode = await _storage.read(key: _storageKeyMode);
      if (savedMode == 'model3d') {
        state = state.copyWith(displayMode: AvatarDisplayMode.model3d);
      } else if (savedMode == 'photo2d') {
        state = state.copyWith(displayMode: AvatarDisplayMode.photo2d);
      }
    } catch (_) {}

    try {
      final savedPhoto = await _storage.read(key: _storageKeyPhoto);
      if (savedPhoto != null && savedPhoto.isNotEmpty) {
        final match = kAvailablePhotos.firstWhere(
          (p) => p.assetPath == savedPhoto,
          orElse: () => kAvailablePhotos.first,
        );
        state = state.copyWith(
          selectedPhotoPath: match.assetPath,
          photoName: match.name,
        );
      }
    } catch (_) {}
  }

  /// Switch between 2D Talking Photo and 3D Model with persistence
  Future<void> setDisplayMode(AvatarDisplayMode mode) async {
    if (state.displayMode == mode) return;
    state = state.copyWith(displayMode: mode);
    try {
      await _storage.write(
        key: _storageKeyMode,
        value: mode == AvatarDisplayMode.photo2d ? 'photo2d' : 'model3d',
      );
    } catch (_) {}
  }

  /// Switch the active 2D photo asset path with persistence
  Future<void> selectPhoto(String assetPath, {String? photoName}) async {
    if (state.selectedPhotoPath == assetPath) return;
    final match = kAvailablePhotos.firstWhere(
      (p) => p.assetPath == assetPath,
      orElse: () => AvatarPhotoOption(
        id: assetPath.contains('Nam') ? 'hdv_nam' : 'hdv_nu',
        name: photoName ?? (assetPath.contains('Nam') ? 'Nam (HDV Nam Thực tế)' : 'Linh (HDV Nữ Thực tế)'),
        subtitle: '',
        assetPath: assetPath,
        gender: assetPath.contains('Nam') ? 'male' : 'female',
        tag: '',
      ),
    );
    state = state.copyWith(
      selectedPhotoPath: match.assetPath,
      photoName: photoName ?? match.name,
    );
    try {
      await _storage.write(key: _storageKeyPhoto, value: assetPath);
    } catch (_) {}
  }

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
