import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../models/trip_model.dart';
import 'trip_stats_card.dart';

class TripHeroHeader extends StatelessWidget {
  final Trip trip;

  const TripHeroHeader({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final startStr = DateFormat('dd/MM').format(trip.startDate);
    final endStr = DateFormat('dd/MM/yyyy').format(trip.endDate);
    final days = trip.daysCount;
    final statusUpper = (trip.status ?? 'CONFIRMED').toUpperCase();
    final statusLabel = statusUpper == 'CONFIRMED' || statusUpper == 'UPCOMING'
        ? 'Đã xác nhận'
        : (statusUpper == 'GENERATED' || statusUpper == 'PLANNING'
            ? 'AI Đã lập kế hoạch'
            : (statusUpper == 'COMPLETED' ? 'Đã hoàn thành' : 'Bản nháp'));

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
                  Colors.black.withOpacity(0.82),
                  Colors.black.withOpacity(0.15),
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
                      _buildHeaderBtn(
                        context,
                        LucideIcons.arrowLeft,
                        () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            MainShell.switchToTab(context, 3);
                          }
                        },
                      ),
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
                      _buildBadge(statusLabel, AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      _buildBadge(trip.destination, AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    trip.title,
                    style: AppTextStyles.h1.copyWith(color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$startStr — $endStr · $days ngày · ${trip.travelers} du khách',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withOpacity(0.85),
                    ),
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
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.25),
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(
          text,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
