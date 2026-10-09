import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../models/trip_model.dart';
import '../../screens/trip_detail_screen.dart';
import 'package:intl/intl.dart';

class FeaturedTripCard extends StatelessWidget {
  final Trip trip;

  const FeaturedTripCard({super.key, required this.trip});

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
                Text('Chuyến đi sắp tới', style: AppTextStyles.h2),
              ],
            ),
            Text('Còn 18 ngày', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              _buildImageHeader(),
              _buildBody(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageHeader() {
    final dateFormat = DateFormat('dd - dd MMM, yyyy');
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          child: Image.network(
            trip.coverImage,
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
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
                decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(9999)),
                child: Text('Sắp diễn ra', style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              if (trip.aiPlanned == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(9999)),
                  child: Text('AI Planned', style: AppTextStyles.caption.copyWith(color: Colors.white)),
                ),
            ],
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: const Icon(Icons.more_vert, color: Colors.white),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.mapPin, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(trip.destination, style: AppTextStyles.caption.copyWith(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 4),
              Text(trip.title, style: AppTextStyles.h1.copyWith(color: Colors.white, fontSize: 24)),
              const SizedBox(height: 4),
              Text('${DateFormat('dd').format(trip.startDate)} - ${DateFormat('dd MMM, yyyy').format(trip.endDate)} • 4 ngày 3 đêm • ${trip.travelers} khách', style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tiến độ chuẩn bị', style: AppTextStyles.label),
              Text('${(trip.progress! * 100).toInt()}% hoàn tất', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: LinearProgressIndicator(
              value: trip.progress,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: (trip.checklist ?? {}).entries.map((e) => _buildChecklistItem(e.key, e.value)).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TripDetailScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Xem chi tiết chuyến đi', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
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
      children: [
        Text(label, style: AppTextStyles.caption.copyWith(color: isDone ? AppColors.success : AppColors.textSecondary)),
        const SizedBox(width: 4),
        Icon(isDone ? LucideIcons.check : LucideIcons.circle, size: 14, color: isDone ? AppColors.success : AppColors.textSecondary),
      ],
    );
  }
}
