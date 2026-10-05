import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class DestinationCard extends StatefulWidget {
  final String title;
  final double rating;
  final String reviews;
  final String imageUrl;
  final String description;

  const DestinationCard({
    super.key,
    required this.title,
    required this.rating,
    required this.reviews,
    required this.imageUrl,
    required this.description,
  });

  @override
  State<DestinationCard> createState() => _DestinationCardState();
}

class _DestinationCardState extends State<DestinationCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 240,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
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
                      widget.imageUrl,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.trending_up, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('Thịnh hành', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 14,
                      child: const Icon(Icons.favorite_border, size: 16, color: Colors.red),
                    ),
                  ),
                  Positioned(
                    bottom: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                    ),
                  ),
                  Positioned(
                    bottom: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 2),
                          Text(widget.rating.toString(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${widget.reviews} đánh giá', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                        Row(
                          children: const [
                            Text('Khám phá', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                          ],
                        )
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
