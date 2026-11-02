import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class ReviewFilterChips extends StatelessWidget {
  final int? selectedRating;
  final String? selectedTripType;
  final String sortBy;
  final ValueChanged<int?> onRatingSelected;
  final ValueChanged<String?> onTripTypeSelected;
  final ValueChanged<String> onSortChanged;

  const ReviewFilterChips({
    super.key,
    required this.selectedRating,
    required this.selectedTripType,
    required this.sortBy,
    required this.onRatingSelected,
    required this.onTripTypeSelected,
    required this.onSortChanged,
  });

  static const tripTypes = [
    {'key': 'solo', 'label': '🎒 Một mình'},
    {'key': 'couple', 'label': '💑 Cặp đôi'},
    {'key': 'family', 'label': '👨‍👩‍👦 Gia đình'},
    {'key': 'friends', 'label': '👥 Bạn bè'},
    {'key': 'business', 'label': '💼 Công tác'},
  ];

  static const sortOptions = [
    {'key': 'newest', 'label': 'Mới nhất'},
    {'key': 'helpful', 'label': 'Hữu ích nhất'},
    {'key': 'rating_high', 'label': 'Điểm cao'},
    {'key': 'rating_low', 'label': 'Điểm thấp'},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sort & General Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lọc & Sắp xếp đánh giá',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              PopupMenuButton<String>(
                initialValue: sortBy,
                onSelected: onSortChanged,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        sortOptions.firstWhere(
                          (opt) => opt['key'] == sortBy,
                          orElse: () => {'label': 'Mới nhất'},
                        )['label']!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
                itemBuilder: (context) => sortOptions
                    .map(
                      (opt) => PopupMenuItem(
                        value: opt['key'],
                        child: Text(
                          opt['label']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: sortBy == opt['key']
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: sortBy == opt['key']
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Scrollable Trip Type & Star Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              // All Trip Types Chip
              _buildChip(
                label: 'Tất cả',
                isSelected: selectedTripType == null && selectedRating == null,
                onTap: () {
                  onTripTypeSelected(null);
                  onRatingSelected(null);
                },
              ),
              const SizedBox(width: 8),

              // Trip Type Chips
              ...tripTypes.map((type) {
                final isSelected = selectedTripType == type['key'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildChip(
                    label: type['label']!,
                    isSelected: isSelected,
                    onTap: () {
                      onTripTypeSelected(isSelected ? null : type['key']);
                    },
                  ),
                );
              }),

              // Rating Filters (5★, 4★, 3★, 2★, 1★)
              ...[5, 4, 3, 2, 1].map((star) {
                final isSelected = selectedRating == star;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildChip(
                    label: '$star ★',
                    isSelected: isSelected,
                    icon: Icons.star,
                    onTap: () {
                      onRatingSelected(isSelected ? null : star);
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
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
                size: 13,
                color: isSelected ? Colors.white : AppColors.warning,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

