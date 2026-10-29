import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../home/models/category_model.dart';

class CategoryChips extends StatelessWidget {
  final List<Category> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelected;

  const CategoryChips({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _buildChip(
            label: 'Tất cả',
            icon: Icons.auto_awesome,
            isSelected: selectedCategoryId == null,
            onTap: () => onSelected(null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: AppSpacing.sm),
            _buildChip(
              label: category.name,
              icon: Icons.place_outlined,
              isSelected: selectedCategoryId == category.id,
              onTap: () => onSelected(category.id),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
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
        ),
      ),
    );
  }
}
