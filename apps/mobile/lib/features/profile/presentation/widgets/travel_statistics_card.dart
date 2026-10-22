import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../domain/entities/profile_entity.dart';

/// Section C: Travel Statistics Card displaying 4 key metrics with custom icons and pill badges.
class TravelStatisticsCard extends StatelessWidget {
  final TravelStats stats;

  const TravelStatisticsCard({super.key, required this.stats});

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.explore, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Hành trình của bạn', style: AppTextStyles.headlineSm),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Tổng kết năm',
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4-Column Statistics Row
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.flight_takeoff,
                  iconBg: AppColors.primaryFixed,
                  iconColor: AppColors.primary,
                  value: stats.totalTrips.toString(),
                  label: 'Chuyến đi',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.pin_drop,
                  iconBg: AppColors.secondaryFixed,
                  iconColor: AppColors.secondary,
                  value: stats.placesVisited.toString(),
                  label: 'Địa điểm',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.location_city,
                  iconBg: AppColors.tertiaryFixed,
                  iconColor: AppColors.tertiary,
                  value: stats.citiesExplored.toString(),
                  label: 'Thành phố',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.bookmark_added,
                  iconBg: AppColors.primaryFixed,
                  iconColor: AppColors.onPrimaryFixedVariant,
                  value: stats.savedPlaces.toString(),
                  label: 'Đã lưu',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.headlineMd.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
