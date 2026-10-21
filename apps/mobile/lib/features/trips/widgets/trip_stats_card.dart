import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';

class TripStatsCard extends StatelessWidget {
  final Trip trip;
  const TripStatsCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final stopsLabel = '${trip.totalStops} điểm';
    final distLabel = '${trip.distanceKm.toStringAsFixed(1)} km';
    final budgetLabel = trip.estimatedBudget.isNotEmpty
        ? trip.estimatedBudget
        : 'Tối ưu';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(LucideIcons.mapPin, stopsLabel, 'Lịch trình'),
          _buildStatItem(LucideIcons.car, distLabel, 'Di chuyển'),
          _buildStatItem(LucideIcons.wallet, budgetLabel, 'Dự tính'),
          _buildStatItem(LucideIcons.zap, '${trip.daysCount} ngày', 'Thời lượng'),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
