import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';

class SuggestionChips extends StatelessWidget {
  const SuggestionChips({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      'Đi đâu cuối tuần?',
      'Ăn gì ở Đà Nẵng?',
      'Lập lịch',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  suggestions[index],
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
