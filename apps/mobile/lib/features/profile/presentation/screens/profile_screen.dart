import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../../core/services/location_service.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../widgets/account_settings_section.dart';
import '../widgets/ai_companion_card.dart';
import '../widgets/logout_button.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_identity_card.dart';
import '../widgets/profile_quick_access.dart';
import '../widgets/travel_badges_section.dart';
import '../widgets/travel_preferences_card.dart';
import '../widgets/travel_statistics_card.dart';

/// TravelSense Profile Screen implementing Enterprise Architecture with Riverpod,
/// responsive layout, pull-to-refresh, real backend integration, and modal editors.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).fetchProfile();
    });
  }

  Future<void> _handleRefresh() async {
    await ref.read(profileProvider.notifier).fetchProfile();
  }

  void _handleLogout() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _handleLocationTap() async {
    await LocationService().requestPermission();
    if (!mounted) return;
    await ref.read(profileProvider.notifier).refreshLocationPermission();
  }

  void _openEditProfileSheet(ProfileEntity profile) {
    final nameController = TextEditingController(text: profile.user.fullName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Chỉnh sửa hồ sơ', style: AppTextStyles.headlineSm),
            const SizedBox(height: 6),
            Text(
              'Cập nhật thông tin hiển thị trên TravelSense.',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Họ và tên',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final newName = nameController.text.trim();
                  if (newName.isNotEmpty) {
                    Navigator.of(ctx).pop();
                    final success = await ref
                        .read(profileProvider.notifier)
                        .updateProfile(fullName: newName);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Cập nhật hồ sơ thành công!'
                              : 'Lỗi cập nhật hồ sơ.',
                        ),
                        backgroundColor: success
                            ? AppColors.success
                            : AppColors.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text('Lưu thay đổi', style: AppTextStyles.labelLg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPreferencesSheet(ProfileEntity profile) {
    var selectedStyle = profile.preferences.style;
    var selectedBudget = profile.preferences.budget;
    var selectedPace = profile.preferences.pace;

    final styles = [
      ('🎒', 'Khám phá (Adventure)'),
      ('🏖️', 'Nghỉ dưỡng (Relax)'),
      ('🏛️', 'Văn hóa & Di sản'),
      ('🍜', 'Ẩm thực & Cà phê'),
    ];

    final budgets = [
      ('🪙', 'Tiết kiệm (Budget)'),
      ('💳', 'Vừa phải (Mid-range)'),
      ('💎', 'Cao cấp (Luxury)'),
    ];

    final paces = [
      ('⚡', 'Năng động (Fast-paced)'),
      ('⚖️', 'Cân bằng (Balanced)'),
      ('☕', 'Thư thả (Slow travel)'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Sở thích du lịch', style: AppTextStyles.headlineSm),
                const SizedBox(height: 4),
                Text(
                  'Chọn phong cách để AI gợi ý đúng gu của bạn.',
                  style: AppTextStyles.bodySm,
                ),
                const SizedBox(height: 16),
                Text('Phong cách:', style: AppTextStyles.labelMd),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: styles.map((s) {
                    final isSel = selectedStyle == s.$2;
                    return ChoiceChip(
                      label: Text('${s.$1} ${s.$2}'),
                      selected: isSel,
                      selectedColor: AppColors.primaryFixed,
                      onSelected: (_) {
                        setModalState(() => selectedStyle = s.$2);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Ngân sách:', style: AppTextStyles.labelMd),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: budgets.map((b) {
                    final isSel = selectedBudget == b.$2;
                    return ChoiceChip(
                      label: Text('${b.$1} ${b.$2}'),
                      selected: isSel,
                      selectedColor: AppColors.secondaryFixed,
                      onSelected: (_) {
                        setModalState(() => selectedBudget = b.$2);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Nhịp độ chuyến đi:', style: AppTextStyles.labelMd),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: paces.map((p) {
                    final isSel = selectedPace == p.$2;
                    return ChoiceChip(
                      label: Text('${p.$1} ${p.$2}'),
                      selected: isSel,
                      selectedColor: AppColors.tertiaryFixed,
                      onSelected: (_) {
                        setModalState(() => selectedPace = p.$2);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final updated = profile.preferences.copyWith(
                        style: selectedStyle,
                        budget: selectedBudget,
                        pace: selectedPace,
                      );
                      ref
                          .read(profileProvider.notifier)
                          .updatePreferences(updated);
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Đã cập nhật sở thích du lịch!'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text('Lưu sở thích', style: AppTextStyles.labelLg),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openQrShareSheet(ProfileEntity profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('Mã QR Hồ sơ', style: AppTextStyles.headlineSm),
            const SizedBox(height: 6),
            Text(
              'Quét mã để kết nối và chia sẻ lịch trình với ${profile.user.fullName}',
              style: AppTextStyles.bodySm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.08),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_2,
                size: 160,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              profile.user.email,
              style: AppTextStyles.labelMd.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openPersonalInfoDialog(ProfileEntity profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Thông tin cá nhân', style: AppTextStyles.headlineSm),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Họ và tên:', profile.user.fullName),
            const SizedBox(height: 8),
            _buildInfoRow('Email:', profile.user.email),
            const SizedBox(height: 8),
            _buildInfoRow('Vai trò:', profile.user.role),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Trạng thái:',
              profile.user.isActive ? 'Đã kích hoạt' : 'Chưa kích hoạt',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Ngày tham gia:',
              '${profile.user.createdAt.day}/${profile.user.createdAt.month}/${profile.user.createdAt.year}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: Text(value, style: AppTextStyles.bodySm)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);

    return Material(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: switch (profileState) {
          ProfileLoading() => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          ProfileError(message: final msg) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 12),
                  Text('Không thể tải hồ sơ', style: AppTextStyles.headlineSm),
                  const SizedBox(height: 6),
                  Text(
                    msg,
                    style: AppTextStyles.bodySm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(profileProvider.notifier).fetchProfile(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ProfileSuccess(profile: final profile) => RefreshIndicator(
            onRefresh: _handleRefresh,
            color: AppColors.primary,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  children: [
                    // Section A: Profile Header
                    ProfileHeader(
                      onSettingsTap: () => _openPersonalInfoDialog(profile),
                      onQrTap: () => _openQrShareSheet(profile),
                    ),
                    const SizedBox(height: 16),

                    // Section B: User Identity Card
                    ProfileIdentityCard(
                      user: profile.user,
                      membershipTier: profile.membershipTier,
                      onEditTap: () => _openEditProfileSheet(profile),
                      onShareTap: () => _openQrShareSheet(profile),
                      onCameraTap: () => _openEditProfileSheet(profile),
                    ),
                    const SizedBox(height: 16),

                    // Section C: Travel Statistics Card
                    TravelStatisticsCard(stats: profile.stats),
                    const SizedBox(height: 16),

                    // Section D: AI Companion Training Card
                    AiCompanionCard(
                      onCustomizeTap: () => _openPreferencesSheet(profile),
                    ),
                    const SizedBox(height: 16),

                    // Section E: Quick Access Grid
                    ProfileQuickAccess(
                      savedPlacesCount: profile.stats.savedPlaces,
                      tripsSummary:
                          '${profile.stats.totalTrips} chuyến đi đã lên kế hoạch',
                      preferencesSummary: profile.preferences.style,
                      onSavedPlacesTap: () => MainShell.switchToTab(context, 1),
                      onMyTripsTap: () => MainShell.switchToTab(context, 3),
                      onPreferencesTap: () => _openPreferencesSheet(profile),
                      onAiAssistantTap: () => MainShell.switchToTab(context, 2),
                    ),
                    const SizedBox(height: 16),

                    // Section F: Travel Preferences Card
                    TravelPreferencesCard(
                      preferences: profile.preferences,
                      onEditTap: () => _openPreferencesSheet(profile),
                    ),
                    const SizedBox(height: 16),

                    // Section G: Travel Badges Section
                    TravelBadgesSection(badges: profile.badges),
                    const SizedBox(height: 16),

                    // Section H: Account Settings Section
                    AccountSettingsSection(
                      locationPermissionLabel: profile.locationPermissionLabel,
                      isLocationGranted: profile.isLocationGranted,
                      onPersonalInfoTap: () => _openPersonalInfoDialog(profile),
                      onNotificationsTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thông báo chuyến đi đang bật'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      onLanguageTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ngôn ngữ hiện tại: Tiếng Việt (VI)'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      onLocationTap: _handleLocationTap,
                      onPrivacyTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bảo mật tài khoản đang an toàn'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Section I: Logout Button & App Version
                    LogoutButton(onLogoutConfirmed: _handleLogout),
                  ],
                ),
              ),
            ),
          ),
          _ => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        },
      ),
    );
  }
}
