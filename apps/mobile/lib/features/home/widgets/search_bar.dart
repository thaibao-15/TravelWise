import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Bạn muốn đi đâu hôm nay?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.mic, color: AppColors.primary, size: 18),
          ),
        ],
      ),
    );
  }
}
