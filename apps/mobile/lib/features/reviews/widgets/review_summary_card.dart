import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class ReviewSummaryCard extends StatelessWidget {
  final double ratingAvg;
  final int totalReviews;
  final Map<int, int> ratingBreakdown;

  const ReviewSummaryCard({
    super.key,
    required this.ratingAvg,
    required this.totalReviews,
    required this.ratingBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Big Score
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ratingAvg.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final isFilled = index < ratingAvg.floor();
                    final isHalf = !isFilled && (index < ratingAvg);
                    return Icon(
                      isFilled
                          ? Icons.star
                          : (isHalf ? Icons.star_half : Icons.star_border),
                      color: AppColors.warning,
                      size: 16,
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  '$totalReviews nhận xét',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(
            height: 90,
            width: 1,
            color: AppColors.border,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),

          // Right: 5-to-1 Star Progress Bars
          Expanded(
            flex: 6,
            child: Column(
              children: List.generate(5, (index) {
                final starNumber = 5 - index;
                final count = ratingBreakdown[starNumber] ?? 0;
                final percentage =
                    totalReviews > 0 ? (count / totalReviews) : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '$starNumber★',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage.clamp(0.0, 1.0),
                            backgroundColor: AppColors.surfaceContainerHigh,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              starNumber >= 4
                                  ? AppColors.primary
                                  : (starNumber == 3
                                      ? AppColors.warning
                                      : AppColors.error),
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$count',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

