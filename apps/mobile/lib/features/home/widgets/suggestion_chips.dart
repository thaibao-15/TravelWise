import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class SuggestionChips extends StatelessWidget {
  const SuggestionChips({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _buildChip('Đi đâu cuối tuần?', Icons.auto_awesome),
          const SizedBox(width: AppSpacing.sm),
          _buildChip('Ăn gì ở Đà Nẵng?', Icons.restaurant_outlined, iconColor: Colors.green),
          const SizedBox(width: AppSpacing.sm),
          _buildChip('Lập lịch...', Icons.calendar_today_outlined, iconColor: Colors.blue),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, {Color iconColor = AppColors.primary}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg * 2),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
