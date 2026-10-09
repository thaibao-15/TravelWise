import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';
import 'itinerary_image_card.dart';

class ItineraryTimelineItem extends StatelessWidget {
  final ItineraryActivity activity;
  final bool isLast;

  const ItineraryTimelineItem({super.key, required this.activity, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    if (activity.isTransfer) {
      return _buildQuickAdd();
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRail(),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAdd() {
    return Padding(
      padding: const EdgeInsets.only(left: 38, bottom: 24),
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.plusCircle, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Flexible(child: Text('Thêm chặng trung chuyển / Cafe nghỉ', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRail() {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        if (!isLast)
          Expanded(
            child: Container(
              width: 2,
              color: AppColors.border,
            ),
          ),
      ],
    );
  }

  Widget _buildCard() {
    if (activity.imageUrl != null) {
      return ItineraryImageCard(activity: activity);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\${activity.startTime} — \${activity.endTime}', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
              if (activity.rating != null)
                Row(
                  children: [
                    const Icon(Icons.star, color: AppColors.warning, size: 14),
                    const SizedBox(width: 4),
                    Text(activity.rating.toString(), style: AppTextStyles.label),
                  ],
                ),
              if (activity.specialBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(activity.specialBadge!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                )
            ],
          ),
          const SizedBox(height: 8),
          Text(activity.title, style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('\${activity.category} · \${activity.duration}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          if (activity.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(activity.description, style: AppTextStyles.bodyMedium),
          ],
          if (activity.bookingStatus != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.checkCircle2, size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(activity.bookingStatus!, style: AppTextStyles.caption.copyWith(color: AppColors.success)),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }
}
