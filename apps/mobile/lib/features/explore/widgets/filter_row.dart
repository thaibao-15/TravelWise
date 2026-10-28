import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class FilterRow extends StatefulWidget {
  final ValueChanged<String>? onFilterSelected;

  const FilterRow({super.key, this.onFilterSelected});

  @override
  State<FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends State<FilterRow> {
  String? _selectedFilter;
  bool _isListView = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          // Horizontally scrollable filter chips to prevent any horizontal overflow
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildFilterChip(
                    'Khoảng cách',
                    id: 'distance',
                    hasDropdown: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip(
                    '4.5+',
                    id: 'rating',
                    icon: Icons.star_border,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip('Giá (\$ - \$\$\$)', id: 'price'),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip('Đang mở cửa', id: 'open'),
                ],
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Pinned List / Map View Toggle
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isListView = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _isListView
                          ? AppColors.background
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.format_list_bulleted,
                      size: 16,
                      color: _isListView
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isListView = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: !_isListView
                          ? AppColors.background
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.map_outlined,
                      size: 16,
                      color: !_isListView
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label, {
    required String id,
    bool hasDropdown = false,
    IconData? icon,
  }) {
    final isSelected = _selectedFilter == id;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = isSelected ? null : id;
        });
        widget.onFilterSelected?.call(id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.primary : AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            if (hasDropdown) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
