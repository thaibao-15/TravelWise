import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class TripsHeader extends StatelessWidget {
  const TripsHeader({super.key});

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Những hành trình', style: AppTextStyles.h1.copyWith(fontSize: 26, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('Plan your next adventure • Quản lý tất cả', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.calendarDays, color: AppColors.textPrimary, size: 20),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(9999),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      const Icon(LucideIcons.plus, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('Tạo mới', style: AppTextStyles.label.copyWith(color: Colors.white)),
                    ],
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
