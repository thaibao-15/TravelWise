import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../../shared/widgets/main_shell.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class TripsHeader extends StatelessWidget {
  final VoidCallback? onCreateTrip;

  const TripsHeader({super.key, this.onCreateTrip});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Những hành trình',
                    style: AppTextStyles.h1.copyWith(fontSize: 26, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Plan your next adventure • Quản lý tất cả',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () => MainShell.switchToTab(context, 2),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.sparkles,
                      color: AppColors.primary,
                      size: 19,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCreateTrip ?? () => MainShell.switchToTab(context, 2),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9999),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        const Icon(LucideIcons.plus, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Tạo mới',
                          style: AppTextStyles.label.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
