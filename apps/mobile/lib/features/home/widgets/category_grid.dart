import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../models/category_model.dart';

class CategoryGrid extends StatelessWidget {
  final List<Category> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?>? onCategorySelected;

  const CategoryGrid({
    Key? key,
    required this.categories,
    this.selectedCategoryId,
    this.onCategorySelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildChip(
              icon: '⌕',
              label: 'Tất cả',
              isSelected: selectedCategoryId == null,
              onTap: () => onCategorySelected?.call(null),
            );
          }

          final category = categories[index - 1];
          return _buildChip(
            icon: _iconFor(category.name),
            label: category.name,
            isSelected: category.id == selectedCategoryId,
            onTap: () => onCategorySelected?.call(
              category.id == selectedCategoryId ? null : category.id,
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip({
    required String icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
            boxShadow: isSelected
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                icon,
                style: TextStyle(
                  fontSize: 15,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _iconFor(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('biển') || normalized.contains('beach')) {
      return '🌊';
    }
    if (normalized.contains('ẩm thực') || normalized.contains('food')) {
      return '🍜';
    }
    if (normalized.contains('cafe') || normalized.contains('cà phê')) {
      return '☕';
    }
    if (normalized.contains('thiên nhiên') || normalized.contains('nature')) {
      return '🌲';
    }
    if (normalized.contains('văn hóa') || normalized.contains('culture')) {
      return '🏛';
    }
    return '📍';
  }
}
