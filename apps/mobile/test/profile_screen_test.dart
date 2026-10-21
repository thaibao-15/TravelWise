import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartz/dartz.dart';
import 'package:mobile/core/error/failures.dart';
import 'package:mobile/features/auth/domain/entities/user.dart';
import 'package:mobile/features/profile/domain/entities/profile_entity.dart';
import 'package:mobile/features/profile/domain/repositories/profile_repository.dart';
import 'package:mobile/features/profile/presentation/providers/profile_provider.dart';
import 'package:mobile/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile/shared/widgets/bottom_nav_bar.dart';

class FakeProfileRepository implements ProfileRepository {
  final ProfileEntity fakeProfile;

  FakeProfileRepository(this.fakeProfile);

  @override
  Future<Either<Failure, ProfileEntity>> getProfile() async {
    return Right(fakeProfile);
  }

  @override
  Future<Either<Failure, User>> updateProfile({
    required int userId,
    String? fullName,
    String? avatarUrl,
  }) async {
    return Right(fakeProfile.user);
  }

  @override
  Future<Either<Failure, TravelPreferences>> updatePreferences(
    TravelPreferences preferences,
  ) async {
    return Right(preferences);
  }
}

void main() {
  final testUser = User(
    id: 1,
    email: 'huy.tran@example.com',
    fullName: 'Huy Trần',
    avatarUrl: null,
    role: 'user',
    isActive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final testProfile = ProfileEntity(
    user: testUser,
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
      favoriteCategories: ['🏖️ Bãi biển', '🍜 Ẩm thực'],
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
    ],
    locationPermissionLabel: 'Đang bật',
    isLocationGranted: true,
  );

  testWidgets('ProfileScreen renders all key sections with user data', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeRepo = FakeProfileRepository(testProfile);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );

    // Let async Riverpod fetchProfile finish
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Section A: Header
    expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
    expect(find.text('TÀI KHOẢN TRAVELSENSE'), findsOneWidget);

    // Section B: User Identity
    expect(find.text('Huy Trần'), findsOneWidget);
    expect(find.textContaining('huy.tran@example.com'), findsOneWidget);
    expect(find.text('Explorer · Cấp 4'), findsOneWidget);
    expect(find.text('Chỉnh sửa'), findsNWidgets(2)); // Identity & Preferences
    expect(find.text('Chia sẻ hồ sơ'), findsOneWidget);

    // Section C: Travel Statistics
    expect(find.text('Hành trình của bạn'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Chuyến đi'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('Địa điểm'), findsOneWidget);

    // Section D: AI Companion
    expect(find.text('Huấn luyện Trợ lý Linh AI'), findsOneWidget);
    expect(find.text('Tùy chỉnh AI'), findsOneWidget);

    // Section E: Quick Access Grid
    expect(find.text('Truy cập nhanh'), findsOneWidget);
    expect(find.text('Địa điểm đã lưu'), findsOneWidget);
    expect(find.text('Lịch trình của tôi'), findsOneWidget);
    expect(find.text('Sở thích du lịch'), findsOneWidget);

    // Section F: Travel Preferences
    expect(find.text('Sở thích du lịch hiện tại'), findsOneWidget);
    expect(find.text('Phong cách'), findsOneWidget);

    // Section G: Badges
    expect(find.text('Dấu ấn hành trình'), findsOneWidget);
    expect(find.text('Beach Lover'), findsOneWidget);

    // Section H: Account Settings
    expect(find.text('Cài đặt tài khoản'), findsOneWidget);
    expect(find.text('Thông tin cá nhân'), findsOneWidget);
    expect(find.text('Quyền vị trí'), findsOneWidget);

    // Section I: Logout & Version
    expect(find.text('Đăng xuất khỏi tài khoản'), findsOneWidget);
    expect(find.textContaining('TravelSense AI'), findsOneWidget);
  });

  testWidgets('CustomBottomNavBar highlights Profile at index 4', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: 4,
            onTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Profile'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });
}
