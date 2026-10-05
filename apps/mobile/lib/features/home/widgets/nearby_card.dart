import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class NearbyCard extends StatelessWidget {
  final String title;
  final String type;
  final double distance;
  final double rating;
  final String imageUrl;

  const NearbyCard({
    super.key,
    required this.title,
    required this.type,
    required this.distance,
    required this.rating,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Image.network(
              imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 2),
                        Text(rating.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(type, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.near_me_outlined, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 2),
                    Text('$distance km', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: const Text('Đang mở cửa', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions, color: AppColors.primary, size: 20),
          )
        ],
      ),
    );
  }
}
