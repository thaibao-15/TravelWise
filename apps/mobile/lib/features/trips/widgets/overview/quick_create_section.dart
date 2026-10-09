import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class QuickCreateSection extends StatelessWidget {
  const QuickCreateSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lên kế hoạch tiếp theo', style: AppTextStyles.h2),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.sparkles, color: AppColors.primary, size: 18),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                          child: Text('10 giây', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Plan with AI', style: AppTextStyles.label),
                    const SizedBox(height: 4),
                    Text('Lịch trình tối ưu tự động theo gu & ngân sách.', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Bắt đầu ngay', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.zap, size: 14, color: AppColors.primary),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.calendarDays, color: AppColors.textPrimary, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Tạo thủ công', style: AppTextStyles.label),
                    const SizedBox(height: 4),
                    Text('Tự do xây dựng từng hoạt động, khách sạn.', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Tự thiết kế', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.arrowRight, size: 14),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ],
        )
      ],
    );
  }
}
