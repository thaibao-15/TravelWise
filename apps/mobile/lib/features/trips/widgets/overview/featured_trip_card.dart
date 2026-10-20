import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../models/trip_model.dart';
import '../../screens/trip_detail_screen.dart';

class FeaturedTripCard extends StatelessWidget {
  final Trip trip;

  const FeaturedTripCard({super.key, required this.trip});

  String _getCountdownLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(trip.startDate.year, trip.startDate.month, trip.startDate.day);
    final diff = start.difference(today).inDays;
    if (diff > 0) return 'Còn $diff ngày';
    if (diff == 0) return 'Hôm nay';
    return 'Đang diễn ra';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.planeTakeoff, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Chuyến đi nổi bật', style: AppTextStyles.h2),
              ],
            ),
            Text(
              _getCountdownLabel(),
              style: AppTextStyles.label.copyWith(color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TripDetailScreen(tripId: trip.id, initialTrip: trip),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildImageHeader(),
                _buildBody(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageHeader() {
    final days = trip.daysCount;
    final nights = (days - 1).clamp(0, 365);
    final durationLabel = nights > 0 ? '$days ngày $nights đêm' : '$days ngày';

    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: Image.network(
            trip.coverImage,
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 190,
              width: double.infinity,
              color: AppColors.primary.withValues(alpha: 0.15),
              child: const Icon(LucideIcons.image, color: AppColors.primary, size: 44),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.9),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  'Sắp diễn ra',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (trip.aiPlanned == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    'AI Planned',
                    style: AppTextStyles.caption.copyWith(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        const Positioned(
          top: 16,
          right: 16,
          child: Icon(Icons.more_vert, color: Colors.white),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.mapPin, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      trip.destination,
                      style: AppTextStyles.caption.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                trip.title,
                style: AppTextStyles.h1.copyWith(color: Colors.white, fontSize: 22),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('dd/MM').format(trip.startDate)} - ${DateFormat('dd/MM/yyyy').format(trip.endDate)} • $durationLabel • ${trip.travelers} khách',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final progressVal = (trip.progress ?? 0.85).clamp(0.0, 1.0);
    final checklistEntries = (trip.checklist ?? {}).entries.toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tiến độ chuẩn bị', style: AppTextStyles.label),
              Text(
                '${(progressVal * 100).toInt()}% hoàn tất',
                style: AppTextStyles.label.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: LinearProgressIndicator(
              value: progressVal,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
              minHeight: 6,
            ),
          ),
          if (checklistEntries.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: checklistEntries
                  .map((e) => _buildChecklistItem(e.key, e.value))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TripDetailScreen(tripId: trip.id, initialTrip: trip),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Xem chi tiết chuyến đi',
                    style: AppTextStyles.label.copyWith(color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.arrowRight, size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String label, bool isDone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: isDone ? AppColors.success : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          isDone ? LucideIcons.check : LucideIcons.circle,
          size: 14,
          color: isDone ? AppColors.success : AppColors.textSecondary,
        ),
      ],
    );
  }
}
