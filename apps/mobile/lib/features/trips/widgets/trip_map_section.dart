import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class TripMapSection extends StatelessWidget {
  const TripMapSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Lá»™ trÃ¬nh báº£n Ä‘á»“', style: AppTextStyles.h2),
        const SizedBox(height: 12),
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            image: const DecorationImage(
              image: NetworkImage('https://images.unsplash.com/photo-1524661135-423995f22d0b'),
              fit: BoxFit.cover,
            ),
          ),
          child: Center(
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(LucideIcons.map, size: 18),
              label: const Text('Xem lá»™ trÃ¬nh chi tiáº¿t'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                elevation: 4,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
