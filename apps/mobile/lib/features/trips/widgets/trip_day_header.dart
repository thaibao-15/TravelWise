import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';

class TripDayHeader extends StatelessWidget {
  final TripDay day;
  const TripDayHeader({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Day \${day.dayIndex} · \${day.title}', style: AppTextStyles.h2),
              const SizedBox(height: 4),
              Text(day.subtitle, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(LucideIcons.slidersHorizontal, size: 20, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
