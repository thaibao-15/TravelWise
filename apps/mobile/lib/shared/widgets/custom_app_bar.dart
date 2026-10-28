import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/spacing.dart';
import '../../core/constants/text_styles.dart';
import 'main_shell.dart';

/// Reusable unified header widget for screens across the TravelWise application.
/// Provides consistent branding, location selection, weather status, notifications, and profile access.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String location;
  final String? weather;
  final bool showWeather;
  final bool hasUnreadNotifications;
  final String? avatarUrl;
  final VoidCallback? onLocationTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final EdgeInsetsGeometry padding;

  const CustomAppBar({
    super.key,
    this.location = 'Đà Nẵng, Việt Nam',
    this.weather = '28°C',
    this.showWeather = true,
    this.hasUnreadNotifications = true,
    this.avatarUrl,
    this.onLocationTap,
    this.onNotificationTap,
    this.onProfileTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
  });

  static const String defaultAvatar =
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?ixlib=rb-4.0.3&auto=format&fit=crop&w=150&q=80';

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Location Selector
          Flexible(
            child: InkWell(
              onTap: onLocationTap ?? () => _showLocationDialog(context),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.mapPin,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        location,
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      LucideIcons.chevronDown,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Right: Weather Pill + Notification Bell + Profile Avatar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Weather indicator (standardized across screens)
              if (showWeather && weather != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.sun,
                        size: 15,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        weather!,
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],

              // Notification Bell
              GestureDetector(
                onTap:
                    onNotificationTap ?? () => _showNotificationInfo(context),
                child: Stack(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.bell,
                        size: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (hasUnreadNotifications)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // Profile Avatar
              GestureDetector(
                onTap: onProfileTap ?? () => MainShell.switchToTab(context, 4),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    backgroundImage: NetworkImage(avatarUrl ?? defaultAvatar),
                    onBackgroundImageError: (exception, stackTrace) {},
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showNotificationInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Bạn có 1 thông báo mới về lịch trình'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLocationDialog(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Vị trí hiện tại: $location'),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
