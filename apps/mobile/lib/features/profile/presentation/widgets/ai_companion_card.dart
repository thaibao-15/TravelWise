import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

/// Section D: AI Companion Training Card for Linh AI personalization.
class AiCompanionCard extends StatelessWidget {
  final VoidCallback onCustomizeTap;

  const AiCompanionCard({super.key, required this.onCustomizeTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            AppColors.primaryFixed.withValues(alpha: 0.35),
            AppColors.surfaceContainerLowest,
            AppColors.secondaryFixed.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(37, 99, 235, 0.08),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Decorative Glow Orb
            Positioned(
              right: -16,
              bottom: -16,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Glowing AI Orb Icon
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.secondaryContainer,
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),

                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Text & Action
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title & Status Dot
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Huấn luyện Trợ lý Linh AI',
                                style: AppTextStyles.headlineSm.copyWith(
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.tertiaryEmerald,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Description
                        Text(
                          'Tùy chỉnh sở thích để AI gợi ý lịch trình cá nhân hóa, điểm ăn uống chuẩn vị và hoạt động độc quyền theo gu của bạn.',
                          style: AppTextStyles.bodySm.copyWith(height: 1.4),
                        ),
                        const SizedBox(height: 12),

                        // Action Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton.icon(
                              onPressed: onCustomizeTap,
                              icon: const Icon(
                                Icons.auto_fix_high,
                                size: 16,
                                color: Colors.white,
                              ),
                              label: Text(
                                'Tùy chỉnh AI',
                                style: AppTextStyles.labelMd.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Text(
                              'Đang sẵn sàng',
                              style: AppTextStyles.labelSm.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
