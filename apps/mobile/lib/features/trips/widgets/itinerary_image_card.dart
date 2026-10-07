import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';

class ItineraryImageCard extends StatelessWidget {
  final ItineraryActivity activity;

  const ItineraryImageCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                child: Image.network(
                  activity.imageUrl!,
                  height: 128,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              if (activity.overlayText != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
                    child: Text(activity.overlayText!, style: AppTextStyles.caption.copyWith(color: Colors.white)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\${activity.startTime} — \${activity.endTime}', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
                const SizedBox(height: 8),
                Text(activity.title, style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text('\${activity.category} · \${activity.duration}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                if (activity.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(activity.description, style: AppTextStyles.bodyMedium),
                ],
                if (activity.aiSuggestion != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.sparkles, size: 16, color: Color(0xFF0284C7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI gợi ý: \${activity.aiSuggestion}',
                            style: AppTextStyles.caption.copyWith(color: const Color(0xFF0369A1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}
