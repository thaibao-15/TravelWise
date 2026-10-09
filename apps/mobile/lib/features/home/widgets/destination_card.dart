import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';

class DestinationCard extends StatefulWidget {
  const DestinationCard({Key? key}) : super(key: key);

  @override
  State<DestinationCard> createState() => _DestinationCardState();
}

class _DestinationCardState extends State<DestinationCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        // Navigate or action
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 220,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                    child: Image.network(
                      'https://images.unsplash.com/photo-1555921015-c262060f0c0b?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80', // Da Nang bridge
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        'Thịnh hành',
                        style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      child: const Icon(LucideIcons.heart, size: 16, color: AppColors.error),
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
                        Text('Đà Nẵng', style: AppTextStyles.h3),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 16, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text('4.9', style: AppTextStyles.label),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Thành phố đáng sống nhất Việt Nam',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        child: Text(
                          'Khám phá',
                          style: AppTextStyles.label.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
