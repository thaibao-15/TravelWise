import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _buildChip('Tất cả', Icons.auto_awesome, true),
          const SizedBox(width: AppSpacing.sm),
          _buildChip('Địa điểm', Icons.place_outlined, false),
          const SizedBox(width: AppSpacing.sm),
          _buildChip('Nhà hàng', Icons.restaurant_outlined, false),
          const SizedBox(width: AppSpacing.sm),
          _buildChip('Khách sạn', Icons.hotel_outlined, false),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? Colors.white : AppColors.textPrimary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
