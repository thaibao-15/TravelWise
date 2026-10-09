import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import 'timeline_item.dart';

class AiItineraryCard extends StatelessWidget {
  const AiItineraryCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.05),
            AppColors.primary.withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lịch trình hoàn hảo cho bạn', style: AppTextStyles.label),
                    Text('Đà Nẵng - 1 ngày', style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const TimelineItem(time: '05:30', title: 'Biển Mỹ Khê', isLast: false),
          const TimelineItem(time: '11:00', title: 'Ngũ Hành Sơn', isLast: false),
          const TimelineItem(time: '18:30', title: 'Cầu Rồng', isLast: true),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text(
                'Xem gợi ý chi tiết',
                style: AppTextStyles.label.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
