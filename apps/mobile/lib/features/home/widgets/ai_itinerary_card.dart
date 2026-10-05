import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import 'timeline_item.dart';

class AiItineraryCard extends StatelessWidget {
  const AiItineraryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: const [
                    Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text('AI Gợi ý theo sở thích của bạn', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Text('Hôm nay', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Một ngày khám phá Đà Nẵng', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Lịch trình tối ưu hóa dựa trên dự báo thời tiết khô ráo và gu ẩm thực bản địa.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
          const SizedBox(height: AppSpacing.lg),
          const TimelineItem(
            time: '05:30 - 08:30 • Buổi sáng',
            title: 'Ngắm bình minh biển Mỹ Khê & Bánh mì Phượng',
            description: 'Đi bộ dọc bờ biển, cà phê muối ven đường',
            tag: 'Hoàn hảo',
            icon: Icons.wb_twilight,
            iconColor: Colors.orange,
            isLast: false,
          ),
          const TimelineItem(
            time: '11:00 - 13:30 • Buổi trưa',
            title: 'Khám phá Ngũ Hành Sơn & Mì Quảng ếch',
            description: 'Hang động Huyền Không mát mẻ & quán Bếp Trang',
            tag: 'Tránh nắng',
            icon: Icons.wb_sunny,
            iconColor: Colors.amber,
            isLast: false,
          ),
          const TimelineItem(
            time: '18:30 - 21:30 • Buổi tối',
            title: 'Dạo cầu Rồng phun lửa & Chợ đêm Helio',
            description: 'Thưởng thức hải sản nướng, không gian nhạc sống',
            tag: '21:00 Phun lửa',
            tagColor: Colors.red,
            icon: Icons.nightlight_round,
            iconColor: Colors.indigo,
            isLast: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('Xem gợi ý chi tiết', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
