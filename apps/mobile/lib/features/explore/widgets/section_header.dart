import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const SectionHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.h2),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: AppTextStyles.bodySmall),
            ],
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Text('Bộ lọc', style: TextStyle(color: AppColors.primary)),
            label: const Icon(Icons.tune, size: 16, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
