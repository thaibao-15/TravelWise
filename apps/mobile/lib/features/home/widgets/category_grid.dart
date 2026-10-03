import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = [
      {'icon': '🏖', 'label': 'Biển', 'color': Colors.blue.shade50},
      {'icon': '🍜', 'label': 'Ẩm thực', 'color': Colors.red.shade50},
      {'icon': '☕', 'label': 'Café', 'color': Colors.brown.shade50},
      {'icon': '🌲', 'label': 'Tự nhiên', 'color': Colors.green.shade50},
      {'icon': '🏛', 'label': 'Văn hóa', 'color': Colors.indigo.shade50},
      {'icon': '🎡', 'label': 'Giải trí', 'color': Colors.purple.shade50},
      {'icon': '📸', 'label': 'Check-in', 'color': Colors.pink.shade50},
      {'icon': '🧘', 'label': 'Nghỉ dưỡng', 'color': Colors.teal.shade50},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.85,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          return Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: categories[index]['color'] as Color,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      categories[index]['icon'] as String,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                categories[index]['label'] as String,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              ),
            ],
          );
        },
      ),
    );
  }
}
