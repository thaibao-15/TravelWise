import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

/// Section H: Account Settings List with real location status and smooth tap feedback.
class AccountSettingsSection extends StatelessWidget {
  final String locationPermissionLabel;
  final bool isLocationGranted;
  final VoidCallback onPersonalInfoTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onLanguageTap;
  final VoidCallback onLocationTap;
  final VoidCallback onPrivacyTap;

  const AccountSettingsSection({
    super.key,
    required this.locationPermissionLabel,
    required this.isLocationGranted,
    required this.onPersonalInfoTap,
    required this.onNotificationsTap,
    required this.onLanguageTap,
    required this.onLocationTap,
    required this.onPrivacyTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(
              Icons.manage_accounts,
              size: 20,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text('Cài đặt tài khoản', style: AppTextStyles.headlineSm),
          ],
        ),
        const SizedBox(height: 12),

        // Settings Container
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.surfaceContainerLow, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(15, 23, 42, 0.04),
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: [
                _buildSettingTile(
                  icon: Icons.person_outline,
                  title: 'Thông tin cá nhân',
                  subtitle: 'Quản lý tên, email và thông tin tài khoản',
                  onTap: onPersonalInfoTap,
                ),
                _buildDivider(),
                _buildSettingTile(
                  icon: Icons.notifications_none,
                  title: 'Thông báo chuyến đi',
                  subtitle: 'Nhắc nhở lịch trình & gợi ý AI',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.outline,
                      ),
                    ],
                  ),
                  onTap: onNotificationsTap,
                ),
                _buildDivider(),
                _buildSettingTile(
                  icon: Icons.language,
                  title: 'Ngôn ngữ',
                  subtitle: 'Tiếng Việt (VI)',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tiếng Việt',
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.outline,
                      ),
                    ],
                  ),
                  onTap: onLanguageTap,
                ),
                _buildDivider(),
                _buildSettingTile(
                  icon: Icons.near_me_outlined,
                  title: 'Quyền vị trí',
                  subtitle: isLocationGranted
                      ? 'Đang bật (Định vị chính xác)'
                      : 'Đang tắt hoặc hạn chế',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isLocationGranted
                              ? AppColors.tertiaryFixed
                              : AppColors.errorContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          locationPermissionLabel,
                          style: AppTextStyles.labelSm.copyWith(
                            fontSize: 11,
                            color: isLocationGranted
                                ? AppColors.onTertiaryFixed
                                : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.outline,
                      ),
                    ],
                  ),
                  onTap: onLocationTap,
                ),
                _buildDivider(),
                _buildSettingTile(
                  icon: Icons.lock_outline,
                  title: 'Quyền riêng tư & Bảo mật',
                  subtitle: 'Mật khẩu & Thiết bị đăng nhập',
                  onTap: onPrivacyTap,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.surfaceContainerLow,
      indent: 64,
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icon Circle
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerLow,
                ),
                child: Icon(icon, size: 20, color: AppColors.onSurface),
              ),
              const SizedBox(width: 14),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.labelLg.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Trailing Widget or Default Chevron
              if (trailing != null)
                trailing
              else
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
