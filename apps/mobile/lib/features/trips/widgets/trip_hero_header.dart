import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';
import 'trip_stats_card.dart';

class TripHeroHeader extends StatelessWidget {
  final Trip trip;

  const TripHeroHeader({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(trip.coverImage),
              fit: BoxFit.cover,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.transparent,
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHeaderBtn(context, LucideIcons.arrowLeft, () => Navigator.pop(context)),
                      Row(
                        children: [
                          _buildHeaderBtn(context, LucideIcons.share, () {}),
                          const SizedBox(width: AppSpacing.sm),
                          _buildHeaderBtn(context, LucideIcons.moreHorizontal, () {}),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      _buildBadge('AI Planned', AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      _buildBadge('28°C Nắng đẹp', AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    trip.title,
                    style: AppTextStyles.h1.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '12 Oct — 16 Oct · 5 days · \${trip.travelers} travelers',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -30,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: TripStatsCard(trip: trip),
        ),
      ],
    );
  }

  Widget _buildHeaderBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
