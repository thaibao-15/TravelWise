import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

class TripReviewsSection extends StatelessWidget {
  const TripReviewsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('ÄÃ¡nh giÃ¡', style: AppTextStyles.h2),
            const SizedBox(width: 8),
            Row(
              children: [
                const Icon(Icons.star, color: AppColors.warning, size: 18),
                const SizedBox(width: 4),
                Text('4.8 (124)', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ],
            )
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
                    radius: 16,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nguyá»…n VÄƒn A', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                        Text('12/10/2023', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Row(
                    children: List.generate(5, (index) => const Icon(Icons.star, color: AppColors.warning, size: 14)),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Text('Lá»‹ch trÃ¬nh ráº¥t há»£p lÃ½, thá»i gian phÃ¢n bá»• tá»‘t. Ráº¥t thÃ­ch há»£p cho gia Ä‘Ã¬nh.', style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
