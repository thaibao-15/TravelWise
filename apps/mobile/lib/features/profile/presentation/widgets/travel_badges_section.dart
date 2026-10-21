import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../domain/entities/profile_entity.dart';

/// Section G: Travel Badges Section with horizontal scrolling cards carousel.
class TravelBadgesSection extends StatelessWidget {
  final List<TravelBadge> badges;

  const TravelBadgesSection({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.military_tech,
                  size: 20,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                Text('Dấu ấn hành trình', style: AppTextStyles.headlineSm),
              ],
            ),
            Text(
              '${badges.length} Huy hiệu',
              style: AppTextStyles.labelSm.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal Carousel
        SizedBox(
          height: 154,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: badges.length,
            separatorBuilder: (_, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final badge = badges[index];
              return _buildBadgeCard(badge, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeCard(TravelBadge badge, int index) {
    // Curated accent colors for badge icons based on index/type
    final (iconBg, tagBg, tagText) = switch (index % 3) {
      0 => (
        AppColors.secondaryFixed,
        AppColors.secondaryFixed.withValues(alpha: 0.5),
        AppColors.onSecondaryFixed,
      ),
      1 => (
        AppColors.primaryFixed,
        AppColors.primaryFixed.withValues(alpha: 0.5),
        AppColors.onPrimaryFixed,
      ),
      _ => (
        AppColors.tertiaryFixed,
        AppColors.tertiaryFixed.withValues(alpha: 0.5),
        AppColors.onTertiaryFixed,
      ),
    };

    return Container(
      width: 154,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceContainerLow, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.04),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(badge.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            badge.title,
            style: AppTextStyles.labelLg.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

          // Count Subtitle
          Text(
            badge.countSubtitle,
            style: AppTextStyles.bodySm.copyWith(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Category Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge.category.toUpperCase(),
              style: AppTextStyles.labelSm.copyWith(
                fontSize: 9,
                letterSpacing: 0.8,
                color: tagText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
