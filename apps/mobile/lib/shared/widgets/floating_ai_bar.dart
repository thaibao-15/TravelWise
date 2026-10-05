import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/spacing.dart';

class FloatingAiBar extends StatelessWidget {
  const FloatingAiBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg * 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text(
              'Bạn muốn gợi ý riêng cho hôm nay?',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Text(
            'Hỏi AI ngay',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
        ],
      ),
    );
  }
}
