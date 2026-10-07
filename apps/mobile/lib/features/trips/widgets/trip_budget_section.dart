import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

class TripBudgetSection extends StatelessWidget {
  const TripBudgetSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text('Chi phÃ­ dá»± kiáº¿n', style: AppTextStyles.h2),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildBudgetRow('Ä‚n uá»‘ng', '800.000 â‚«', 0.2, AppColors.primary),
              const SizedBox(height: 12),
              _buildBudgetRow('Di chuyá»ƒn', '500.000 â‚«', 0.15, AppColors.secondary),
              const SizedBox(height: 12),
              _buildBudgetRow('VÃ© tham quan', '600.000 â‚«', 0.15, AppColors.warning),
              const SizedBox(height: 12),
              _buildBudgetRow('LÆ°u trÃº', '2.000.000 â‚«', 0.5, AppColors.success),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: AppColors.border),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tá»•ng cá»™ng', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                  Text('3.900.000 â‚«', style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetRow(String label, String amount, double ratio, Color color) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: AppTextStyles.bodyMedium),
        ),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(amount, style: AppTextStyles.bodyMedium, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
