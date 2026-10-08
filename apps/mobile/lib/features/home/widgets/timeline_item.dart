import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';

class TimelineItem extends StatelessWidget {
  final String time;
  final String title;
  final bool isLast;

  const TimelineItem({
    Key? key,
    required this.time,
    required this.title,
    this.isLast = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            time,
            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: AppColors.primary.withOpacity(0.3),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              title,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}
