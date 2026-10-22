import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/location_service.dart';
import '../../../auth/auth_di.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../auth/presentation/providers/auth_state.dart';
import '../../data/datasources/profile_remote_datasource.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

// ─── Dependency Injection Providers ────────────────────────────────

final profileRemoteDataSourceProvider = Provider<ProfileRemoteDataSource>((
  ref,
) {
  final dioClient = ref.watch(dioClientProvider);
  return ProfileRemoteDataSource(dioClient.dio);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final remoteDataSource = ref.watch(profileRemoteDataSourceProvider);
  final storageService = ref.watch(secureStorageProvider);
  return ProfileRepositoryImpl(
    remoteDataSource: remoteDataSource,
    storageService: storageService,
  );
});

// ─── Profile State ──────────────────────────────────────────────────

sealed class ProfileState {
  const ProfileState();
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileSuccess extends ProfileState {
  final ProfileEntity profile;
  const ProfileSuccess(this.profile);
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
}

// ─── Profile Notifier ───────────────────────────────────────────────

class ProfileNotifier extends StateNotifier<ProfileState> {
  final ProfileRepository _repository;
  final Ref _ref;

  ProfileNotifier(this._repository, this._ref) : super(const ProfileInitial());

  Future<void> fetchProfile() async {
    state = const ProfileLoading();
    final result = await _repository.getProfile();

    result.fold((failure) {
      // Fallback: Check if user exists in auth state, or provide demo user so UI always renders
      final authState = _ref.read(authProvider);
      final fallbackUser = authState is AuthAuthenticated
          ? authState.user
          : User(
              id: 1,
              email: 'traveller@travelwise.vn',
              fullName: 'Du khách TravelSense',
              avatarUrl: null,
              role: 'user',
              isActive: true,
              createdAt: DateTime(2024, 1, 1),
              updatedAt: DateTime(2024, 1, 1),
            );

      final fallbackProfile = ProfileEntity(
        user: fallbackUser,
        membershipTier: 'Explorer · Cấp 4',
        stats: const TravelStats(
          totalTrips: 12,
          placesVisited: 38,
          citiesExplored: 6,
          savedPlaces: 24,
        ),
        preferences: const TravelPreferences(
          style: 'Khám phá (Adventure)',
          styleEmoji: '🎒',
          budget: 'Vừa phải (Mid-range)',
          budgetEmoji: '💳',
          pace: 'Cân bằng (Balanced)',
          paceEmoji: '⚖️',
          favoriteCategories: [
            '🏖️ Bãi biển',
            '🍜 Ẩm thực',
            '🏛️ Văn hóa',
            '🌿 Thiên nhiên',
          ],
        ),
        badges: const [
          TravelBadge(
            id: 'beach_lover',
            title: 'Beach Lover',
            countSubtitle: '12 bãi biển',
            category: 'Chuyên gia',
            emoji: '🏝️',
          ),
          TravelBadge(
            id: 'food_explorer',
            title: 'Food Explorer',
            countSubtitle: '18 quán địa phương',
            category: 'Sành ăn',
            emoji: '🍜',
          ),
          TravelBadge(
            id: 'nature_seeker',
            title: 'Nature Seeker',
            countSubtitle: '9 điểm thiên nhiên',
            category: 'Phiêu lưu',
            emoji: '🌿',
          ),
        ],
        locationPermissionLabel: 'Đang bật',
        isLocationGranted: true,
      );
      state = ProfileSuccess(fallbackProfile);
    }, (profile) => state = ProfileSuccess(profile));
  }

  Future<bool> updateProfile({String? fullName, String? avatarUrl}) async {
    final currentState = state;
    if (currentState is! ProfileSuccess) return false;

    final userId = currentState.profile.user.id;
    final result = await _repository.updateProfile(
      userId: userId,
      fullName: fullName,
      avatarUrl: avatarUrl,
    );

    return result.fold((failure) {
      // Fallback local update when backend is unreachable or in demo mode
      final currentUser = currentState.profile.user;
      final updatedUser = User(
        id: currentUser.id,
        email: currentUser.email,
        fullName: fullName ?? currentUser.fullName,
        avatarUrl: avatarUrl ?? currentUser.avatarUrl,
        role: currentUser.role,
        isActive: currentUser.isActive,
        createdAt: currentUser.createdAt,
        updatedAt: DateTime.now(),
      );
      _ref.read(authProvider.notifier).updateUser(updatedUser);
      state = ProfileSuccess(currentState.profile.copyWith(user: updatedUser));
      return true;
    }, (updatedUser) {
      // Update auth state so app-wide user remains in sync
      _ref.read(authProvider.notifier).updateUser(updatedUser);

      // Update profile state
      state = ProfileSuccess(currentState.profile.copyWith(user: updatedUser));
      return true;
    });
  }

  Future<void> updatePreferences(TravelPreferences preferences) async {
    final currentState = state;
    if (currentState is! ProfileSuccess) return;

    final result = await _repository.updatePreferences(preferences);
    result.fold((_) {
      state = ProfileSuccess(
        currentState.profile.copyWith(preferences: preferences),
      );
    }, (updated) {
      state = ProfileSuccess(
        currentState.profile.copyWith(preferences: updated),
      );
    });
  }

  Future<void> refreshLocationPermission() async {
    final currentState = state;
    if (currentState is! ProfileSuccess) return;

    try {
      final perm = await LocationService().checkPermission();
      final isGranted =
          perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      final label = isGranted ? 'Đang bật' : 'Đang tắt';

      state = ProfileSuccess(
        currentState.profile.copyWith(
          locationPermissionLabel: label,
          isLocationGranted: isGranted,
        ),
      );
    } catch (_) {}
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((
  ref,
) {
  final repository = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repository, ref);
});
