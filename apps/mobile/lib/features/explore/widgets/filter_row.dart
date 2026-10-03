import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class FilterRow extends StatelessWidget {
  const FilterRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _buildFilterChip('Khoảng cách', hasDropdown: true),
          const SizedBox(width: AppSpacing.sm),
          _buildFilterChip('4.5+', icon: Icons.star_border),
          const SizedBox(width: AppSpacing.sm),
          _buildFilterChip('Giá (\$ - \$\$\$)'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.format_list_bulleted, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.map_outlined, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {bool hasDropdown = false, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          if (hasDropdown) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ],
      ),
    );
  }
}
