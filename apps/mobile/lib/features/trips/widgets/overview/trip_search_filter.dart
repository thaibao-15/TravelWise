import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class TripSearchFilter extends StatelessWidget {
  final String activeFilter;
  final Function(String) onFilterChanged;
  final Function(String) onSearchChanged;

  const TripSearchFilter({
    super.key,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      {'id': 'all', 'label': 'Tất cả (4)'},
      {'id': 'upcoming', 'label': 'Sắp tới (1)'},
      {'id': 'planning', 'label': 'Đang lên kế hoạch (1)'},
      {'id': 'draft', 'label': 'Bản nháp (1)'},
      {'id': 'completed', 'label': 'Đã qua (1)'},
    ];

    return Column(
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(LucideIcons.search, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm chuyến đi hoặc điểm đến...',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const Icon(LucideIcons.slidersHorizontal, color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = filters[index];
              final isActive = activeFilter == filter['id'];
              return GestureDetector(
                onTap: () => onFilterChanged(filter['id']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: isActive ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(
                    filter['label']!,
                    style: AppTextStyles.label.copyWith(
                      color: isActive ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

