import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';

class TripDaySelector extends ConsumerWidget {
  final List<TripDay> days;
  const TripDaySelector({super.key, required this.days});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDay = ref.watch(selectedDayProvider);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = days[index];
          final isActive = day.dayIndex == selectedDay;

          return GestureDetector(
            onTap: () => ref.read(selectedDayProvider.notifier).state = day.dayIndex,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isActive ? null : Border.all(color: AppColors.border),
                boxShadow: isActive
                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                    : [],
              ),
              child: Row(
                children: [
                  if (isActive) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    'DAY \${day.dayIndex} · \${day.date.day} Oct',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isActive ? Colors.white : AppColors.textPrimary,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
