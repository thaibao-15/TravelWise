import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../models/place_model.dart';

class PlaceCard extends StatelessWidget {
  final Place place;

  const PlaceCard({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
                child: Image.network(
                  place.imageUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: AppSpacing.md,
                left: AppSpacing.md,
                child: Row(
                  children: [
                    if (place.tags.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        ),
                        child: Text(place.tags.first, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(width: AppSpacing.xs),
                    if (place.isOpen)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        ),
                        child: const Text('• Đang mở cửa', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: Row(
                  children: const [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 14,
                      child: Icon(Icons.bookmark_border, size: 16, color: AppColors.textPrimary),
                    ),
                    SizedBox(width: AppSpacing.xs),
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 14,
                      child: Icon(Icons.share_outlined, size: 16, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        place.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      place.price,
                      style: TextStyle(color: place.price == 'Miễn phí' ? AppColors.success : AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  place.description,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(Icons.star, color: AppColors.primary, size: 14),
                    const SizedBox(width: 4),
                    Text('${place.rating}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 4),
                    Text('(${place.reviews > 1000 ? '${(place.reviews / 1000).toStringAsFixed(1)}K' : place.reviews})', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(width: AppSpacing.md),
                    const Icon(Icons.location_on_outlined, color: AppColors.textSecondary, size: 14),
                    const SizedBox(width: 4),
                    Text('${place.distance} km', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.add, size: 14, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text('Thêm chuyến đi', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
