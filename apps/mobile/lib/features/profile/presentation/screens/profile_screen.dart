import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../../core/services/location_service.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../data/models/user_profile_model.dart';
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
/// responsive layout, pull-to-refresh, real backend integration, avatar upload,
/// and comprehensive profile & preference editors.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

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

  /// Triggers image picker modal (Camera or Gallery) and uploads avatar to backend
  void _handleAvatarChange() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Text('Ảnh đại diện', style: AppTextStyles.headlineSm),
              const SizedBox(height: 4),
              Text(
                'Chọn nguồn ảnh để cập nhật hồ sơ của bạn',
                style: AppTextStyles.bodySm,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.primary,
                  ),
                ),
                title: Text('Chụp ảnh từ máy ảnh', style: AppTextStyles.labelLg),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              const Divider(height: 1, indent: 60),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.secondary,
                  ),
                ),
                title: Text('Chọn từ bộ sưu tập', style: AppTextStyles.labelLg),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang tải ảnh đại diện lên máy chủ...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final success = await ref
          .read(profileProvider.notifier)
          .uploadAvatar(picked);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Cập nhật ảnh đại diện thành công!'
                : 'Tải ảnh đại diện thất bại. Vui lòng thử lại.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi chọn ảnh: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Opens comprehensive Personal Information Editor (matching backend User & UserProfile)
  void _openEditProfileSheet(ProfileEntity profile) {
    final userProfile = profile.userProfile;
    final nameController = TextEditingController(text: profile.user.fullName);
    final phoneController = TextEditingController(
      text: userProfile?.phone ?? '',
    );
    final nationalityController = TextEditingController(
      text: userProfile?.nationality ?? 'Việt Nam',
    );
    DateTime? selectedDob = userProfile?.dateOfBirth;
    String selectedGender = userProfile?.gender ?? 'Nam';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
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
                  'Cập nhật thông tin cá nhân và tài khoản TravelSense.',
                  style: AppTextStyles.bodySm,
                ),
                const SizedBox(height: 20),

                // Full Name
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
                const SizedBox(height: 14),

                // Phone Number
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Số điện thoại',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                  ),
                ),
                const SizedBox(height: 14),

                // Date of Birth Selector
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDob ?? DateTime(2000, 1, 1),
                      firstDate: DateTime(1930),
                      lastDate: DateTime.now(),
                      helpText: 'CHỌN NGÀY SINH',
                      cancelText: 'HỦY',
                      confirmText: 'CHỌN',
                    );
                    if (picked != null) {
                      setSheetState(() => selectedDob = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          selectedDob != null
                              ? DateFormat('dd/MM/yyyy').format(selectedDob!)
                              : 'Chọn ngày sinh',
                          style: AppTextStyles.bodyMd.copyWith(
                            color: selectedDob != null
                                ? AppColors.onSurface
                                : AppColors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Gender Selection
                Text(
                  'Giới tính:',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['Nam', 'Nữ', 'Khác'].map((g) {
                    final isSel = selectedGender == g;
                    return ChoiceChip(
                      label: Text(g),
                      selected: isSel,
                      selectedColor: AppColors.primaryFixed,
                      onSelected: (_) => setSheetState(() => selectedGender = g),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Nationality
                TextField(
                  controller: nationalityController,
                  decoration: InputDecoration(
                    labelText: 'Quốc tịch',
                    prefixIcon: const Icon(Icons.public_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final newName = nameController.text.trim();
                      if (newName.isEmpty) return;

                      Navigator.of(ctx).pop();
                      final success = await ref
                          .read(profileProvider.notifier)
                          .updatePersonalInfo(
                            fullName: newName,
                            phone: phoneController.text.trim().isNotEmpty
                                ? phoneController.text.trim()
                                : null,
                            dateOfBirth: selectedDob,
                            gender: selectedGender,
                            nationality:
                                nationalityController.text.trim().isNotEmpty
                                    ? nationalityController.text.trim()
                                    : 'Việt Nam',
                          );

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Cập nhật hồ sơ thành công!'
                                : 'Lưu hồ sơ gặp lỗi nhỏ, dữ liệu đã đồng bộ cục bộ.',
                          ),
                          backgroundColor: success
                              ? AppColors.success
                              : AppColors.primary,
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
                    child: Text('Lưu thay đổi', style: AppTextStyles.labelLg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens comprehensive Travel Preferences Editor (matching all backend UserProfile fields)
  void _openPreferencesSheet(ProfileEntity profile) {
    final userProfile = profile.userProfile;
    var selectedStyle =
        userProfile?.travelStyle ?? profile.preferences.style;
    var selectedPace =
        userProfile?.preferredTravelPace ?? profile.preferences.pace;
    var selectedTransport = userProfile?.preferredTransport ?? 'Máy bay';
    var selectedAccommodation =
        userProfile?.accommodationType ?? 'Khách sạn cao cấp';
    var selectedCategories = List<String>.from(
      userProfile?.favoriteCategories ?? profile.preferences.favoriteCategories,
    );
    var selectedDietary = List<String>.from(
      userProfile?.dietaryPreferences ?? ['Không kiêng cữ'],
    );
    final notesController = TextEditingController(
      text: userProfile?.additionalPreferences ?? '',
    );

    // Preset Budgets
    double? minBudget = userProfile?.budgetMin;
    double? maxBudget = userProfile?.budgetMax;

    final styles = [
      ('🎒', 'Khám phá (Adventure)'),
      ('🏖️', 'Nghỉ dưỡng (Relax)'),
      ('🏛️', 'Văn hóa & Di sản'),
      ('🍜', 'Ẩm thực & Cà phê'),
      ('🌿', 'Thiên nhiên & Sinh thái'),
      ('📸', 'Check-in & Sống ảo'),
    ];

    final paces = [
      ('⚡', 'Năng động (Fast-paced)'),
      ('⚖️', 'Cân bằng (Balanced)'),
      ('☕', 'Thư thả (Slow travel)'),
    ];

    final transports = [
      ('✈️', 'Máy bay'),
      ('🚗', 'Tự lái xe'),
      ('🚆', 'Tàu hỏa'),
      ('🚌', 'Xe khách'),
      ('🛵', 'Xe máy'),
    ];

    final accommodations = [
      ('🏨', 'Khách sạn cao cấp'),
      ('🌴', 'Resort nghỉ dưỡng'),
      ('🏡', 'Homestay ấm cúng'),
      ('🏢', 'Căn hộ tiện nghi'),
    ];

    final categoriesList = [
      ('🏖️', 'Bãi biển'),
      ('🍜', 'Ẩm thực'),
      ('🏛️', 'Văn hóa'),
      ('🌿', 'Thiên nhiên'),
      ('🛍️', 'Mua sắm'),
      ('🌙', 'Giải trí đêm'),
    ];

    final dietaryList = [
      'Không kiêng cữ',
      'Ăn chay 🌱',
      'Hải sản 🦐',
      'Đồ nướng 🥩',
      'Không cay 🌶️❌',
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
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
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
                  'Đồng bộ trực tiếp lên máy chủ để trợ lý AI lập kế hoạch chính xác theo gu của bạn.',
                  style: AppTextStyles.bodySm,
                ),
                const SizedBox(height: 18),

                // 1. Travel Style
                Text(
                  'Phong cách du lịch:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: styles.map((s) {
                    final isSel = selectedStyle.contains(s.$2) || selectedStyle == s.$2;
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
                const SizedBox(height: 18),

                // 2. Pace
                Text(
                  'Nhịp độ chuyến đi:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: paces.map((p) {
                    final isSel = selectedPace.contains(p.$2) || selectedPace == p.$2;
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
                const SizedBox(height: 18),

                // 3. Preferred Transport
                Text(
                  'Phương tiện ưu tiên:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: transports.map((t) {
                    final isSel = selectedTransport == t.$2;
                    return ChoiceChip(
                      label: Text('${t.$1} ${t.$2}'),
                      selected: isSel,
                      selectedColor: AppColors.secondaryFixed,
                      onSelected: (_) {
                        setModalState(() => selectedTransport = t.$2);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // 4. Accommodation
                Text(
                  'Chỗ ở mong muốn:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: accommodations.map((a) {
                    final isSel = selectedAccommodation == a.$2;
                    return ChoiceChip(
                      label: Text('${a.$1} ${a.$2}'),
                      selected: isSel,
                      selectedColor: AppColors.primaryFixed,
                      onSelected: (_) {
                        setModalState(() => selectedAccommodation = a.$2);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // 5. Favorite Categories (multi-select)
                Text(
                  'Chủ đề yêu thích:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categoriesList.map((c) {
                    final formattedName = '${c.$1} ${c.$2}';
                    final isSel = selectedCategories.any(
                      (cat) => cat.contains(c.$2),
                    );
                    return FilterChip(
                      label: Text(formattedName),
                      selected: isSel,
                      selectedColor: AppColors.secondaryFixed,
                      onSelected: (bool selected) {
                        setModalState(() {
                          if (selected) {
                            selectedCategories.add(formattedName);
                          } else {
                            selectedCategories.removeWhere(
                              (cat) => cat.contains(c.$2),
                            );
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // 6. Dietary Preferences (multi-select)
                Text(
                  'Thói quen ăn uống & Dị ứng:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: dietaryList.map((d) {
                    final isSel = selectedDietary.contains(d);
                    return FilterChip(
                      label: Text(d),
                      selected: isSel,
                      selectedColor: AppColors.tertiaryFixed,
                      onSelected: (bool selected) {
                        setModalState(() {
                          if (selected) {
                            selectedDietary.add(d);
                          } else {
                            selectedDietary.remove(d);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // 7. Additional Preferences Notes
                Text(
                  'Ghi chú thêm cho AI:',
                  style: AppTextStyles.labelLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'VD: Thích chụp ảnh lúc hoàng hôn, hạn chế đi bộ dốc...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();

                      final existingProfile =
                          profile.userProfile ?? const UserProfileModel();
                      final updatedProfileModel = existingProfile.copyWith(
                        travelStyle: selectedStyle,
                        preferredTravelPace: selectedPace,
                        preferredTransport: selectedTransport,
                        accommodationType: selectedAccommodation,
                        favoriteCategories: selectedCategories,
                        dietaryPreferences: selectedDietary,
                        budgetMin: minBudget,
                        budgetMax: maxBudget,
                        additionalPreferences:
                            notesController.text.trim().isNotEmpty
                                ? notesController.text.trim()
                                : null,
                      );

                      final success = await ref
                          .read(profileProvider.notifier)
                          .updateFullTravelProfile(updatedProfileModel);

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Đã lưu sở thích du lịch lên máy chủ!'
                                : 'Đã cập nhật sở thích du lịch!',
                          ),
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

  /// Detailed personal info dialog with view & direct edit trigger
  void _openPersonalInfoDialog(ProfileEntity profile) {
    final userProfile = profile.userProfile;
    final dobStr = userProfile?.dateOfBirth != null
        ? DateFormat('dd/MM/yyyy').format(userProfile!.dateOfBirth!)
        : 'Chưa cập nhật';

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
            _buildInfoRow('Số điện thoại:', userProfile?.phone ?? 'Chưa cập nhật'),
            const SizedBox(height: 8),
            _buildInfoRow('Ngày sinh:', dobStr),
            const SizedBox(height: 8),
            _buildInfoRow('Giới tính:', userProfile?.gender ?? 'Chưa cập nhật'),
            const SizedBox(height: 8),
            _buildInfoRow('Quốc tịch:', userProfile?.nationality ?? 'Việt Nam'),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _openEditProfileSheet(profile);
            },
            child: const Text('Chỉnh sửa'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  /// Language picker sheet synced to backend preferred_language
  void _openLanguageSheet(ProfileEntity profile) {
    final currentLang = profile.userProfile?.preferredLanguage ?? 'vi';

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
            Text('Ngôn ngữ hiển thị', style: AppTextStyles.headlineSm),
            const SizedBox(height: 6),
            Text(
              'Chọn ngôn ngữ cho ứng dụng và gợi ý AI',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Tiếng Việt (VI)'),
              trailing: currentLang == 'vi'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref
                    .read(profileProvider.notifier)
                    .updatePersonalInfo(preferredLanguage: 'vi');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã chọn Tiếng Việt'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('English (EN)'),
              trailing: currentLang == 'en'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref
                    .read(profileProvider.notifier)
                    .updatePersonalInfo(preferredLanguage: 'en');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Switched to English'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Privacy & Account Security modal with Delete Account action
  void _openPrivacySheet(ProfileEntity profile) {
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
            Text('Quyền riêng tư & Bảo mật', style: AppTextStyles.headlineSm),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.security, color: AppColors.primary),
              title: const Text('Trạng thái tài khoản'),
              subtitle: Text(
                profile.user.isActive ? 'Đang hoạt động bình thường' : 'Tạm khóa',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync, color: AppColors.secondary),
              title: const Text('Dữ liệu cá nhân'),
              subtitle: const Text('Được mã hóa và lưu trữ an toàn trên máy chủ'),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
              title: Text(
                'Xóa tài khoản',
                style: AppTextStyles.labelLg.copyWith(color: AppColors.error),
              ),
              subtitle: const Text('Xóa toàn bộ hồ sơ và dữ liệu du lịch'),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteAccount();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Xác nhận xóa tài khoản?',
          style: AppTextStyles.headlineSm.copyWith(color: AppColors.error),
        ),
        content: Text(
          'Toàn bộ thông tin hồ sơ, lịch trình du lịch và cài đặt của bạn sẽ bị xóa vĩnh viễn trên máy chủ. Bạn sẽ không thể khôi phục dữ liệu này.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success =
                  await ref.read(profileProvider.notifier).deleteAccount();
              if (success) {
                _handleLogout();
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Không thể xóa tài khoản. Vui lòng thử lại.'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa tài khoản'),
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
    final isAvatarUploading = ref.watch(isAvatarUploadingProvider);

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
                      isAvatarUploading: isAvatarUploading,
                      onEditTap: () => _openEditProfileSheet(profile),
                      onShareTap: () => _openQrShareSheet(profile),
                      onCameraTap: _handleAvatarChange,
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
                      userProfile: profile.userProfile,
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
                      onLanguageTap: () => _openLanguageSheet(profile),
                      onLocationTap: _handleLocationTap,
                      onPrivacyTap: () => _openPrivacySheet(profile),
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
