import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../domain/entities/profile_entity.dart';

/// Section F: Travel Preferences Card displaying style, budget, pace, and categories.
class TravelPreferencesCard extends StatelessWidget {
  final TravelPreferences preferences;
  final VoidCallback onEditTap;

  const TravelPreferencesCard({
    super.key,
    required this.preferences,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.psychology,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Sở thích du lịch hiện tại',
                        style: AppTextStyles.headlineSm.copyWith(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onEditTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Chỉnh sửa',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Preference Items
          _buildPreferenceRow(
            label: 'Phong cách',
            emoji: preferences.styleEmoji,
            value: preferences.style,
          ),
          const SizedBox(height: 8),
          _buildPreferenceRow(
            label: 'Ngân sách',
            emoji: preferences.budgetEmoji,
            value: preferences.budget,
          ),
          const SizedBox(height: 8),
          _buildPreferenceRow(
            label: 'Nhịp độ',
            emoji: preferences.paceEmoji,
            value: preferences.pace,
          ),
          const SizedBox(height: 14),

          // Favorite Categories Strip
          Text(
            'Chủ đề ưa chuộng:',
            style: AppTextStyles.bodySm.copyWith(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: preferences.favoriteCategories.map((category) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.secondaryFixed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  category,
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSecondaryFixed,
                    fontSize: 11,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceRow({
    required String label,
    required String emoji,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    value,
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
