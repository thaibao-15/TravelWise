import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../models/trip_model.dart';
import '../../screens/trip_detail_screen.dart';
import 'package:intl/intl.dart';

class TripListCard extends StatelessWidget {
  final Trip trip;

  const TripListCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TripDetailScreen()));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            _buildImageHeader(),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildImageHeader() {
    Color badgeColor = AppColors.textSecondary;
    String badgeText = '';
    if (trip.status == 'planning') { badgeColor = AppColors.warning; badgeText = 'Đang lên kế hoạch'; }
    if (trip.status == 'draft') { badgeColor = AppColors.textSecondary; badgeText = 'Bản nháp'; }
    if (trip.status == 'completed') { badgeColor = AppColors.primary; badgeText = 'Đã hoàn thành'; }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          child: Image.network(
            trip.coverImage,
            height: 160,
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
                colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(9999)),
            child: Text(badgeText, style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
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
              Text(trip.title, style: AppTextStyles.h1.copyWith(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text(trip.category ?? '', style: AppTextStyles.caption.copyWith(color: Colors.white)),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('\ - \ • \ ngày', style: AppTextStyles.label),
              const SizedBox(height: 4),
              Text('\ hoạt động đã lưu', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          Row(
            children: [
              if (trip.status == 'draft')
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.edit3, color: AppColors.textPrimary, size: 18),
                )
              else if (trip.status == 'completed')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
                  child: Text('Tái tạo lịch trình', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                )
              else ...[
                const CircleAvatar(radius: 12, backgroundColor: Colors.blue, child: Text('A', style: TextStyle(fontSize: 10, color: Colors.white))),
                const SizedBox(width: -8),
                const CircleAvatar(radius: 12, backgroundColor: Colors.orange, child: Text('T', style: TextStyle(fontSize: 10, color: Colors.white))),
                const SizedBox(width: 12),
                const Icon(LucideIcons.chevronRight, color: AppColors.textSecondary, size: 20),
              ]
            ],
          )
        ],
      ),
    );
  }
}

