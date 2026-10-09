import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';

/// Mock recommendation card for "Cà phê Trình Biển".
/// Uses a gradient placeholder instead of a network image.
class PlaceRecommendationCard extends StatelessWidget {
  const PlaceRecommendationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image / gradient placeholder ─────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl)),
            child: Container(
              height: 130,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0EA5E9),
                    Color(0xFF2563EB),
                    Color(0xFF1E3A5F),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Decorative wave-like circles
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.07),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -10,
                    left: 40,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05),
                      ),
                    ),
                  ),
                  // Text overlay
                  Positioned(
                    bottom: 12,
                    left: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Mở cửa',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Cà phê Trình Biển',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                  color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Beach icon top-right
                  const Positioned(
                    top: 12,
                    right: 14,
                    child: Text('🏖️', style: TextStyle(fontSize: 28)),
                  ),
                ],
              ),
            ),
          ),

          // ── Info section ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rating + distance row
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 4),
                    const Text(
                      '4.8',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 1,
                      height: 12,
                      color: AppColors.border,
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    const Text(
                      '850m',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Đường Võ Nguyên Giáp',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '✨ Đặc sản: Cà phê bơ béo ngậy',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.directions,
                        label: 'Chỉ đường',
                        color: AppColors.primary,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.restaurant_menu,
                        label: 'Xem menu',
                        color: AppColors.textSecondary,
                        outlined: true,
                        onTap: () {},
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: outlined
              ? Border.all(color: AppColors.border, width: 1.5)
              : null,
          boxShadow: outlined
              ? []
              : [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: outlined ? AppColors.textSecondary : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color:
                    outlined ? AppColors.textSecondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
