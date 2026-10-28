import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

/// Section E: Quick Access 2x2 Grid with smooth feedback and navigation.
class ProfileQuickAccess extends StatelessWidget {
  final int savedPlacesCount;
  final String tripsSummary;
  final String preferencesSummary;
  final VoidCallback onSavedPlacesTap;
  final VoidCallback onMyTripsTap;
  final VoidCallback onPreferencesTap;
  final VoidCallback onAiAssistantTap;

  const ProfileQuickAccess({
    super.key,
    required this.savedPlacesCount,
    required this.tripsSummary,
    required this.preferencesSummary,
    required this.onSavedPlacesTap,
    required this.onMyTripsTap,
    required this.onPreferencesTap,
    required this.onAiAssistantTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Truy cập nhanh', style: AppTextStyles.headlineSm),
            Text(
              '4 mục',
              style: AppTextStyles.labelSm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2-Column Grid
        Row(
          children: [
            Expanded(
              child: _buildCard(
                icon: Icons.bookmarks,
                iconBg: AppColors.primaryFixed,
                iconColor: AppColors.primary,
                title: 'Địa điểm đã lưu',
                subtitle: '$savedPlacesCount địa điểm đã lưu',
                onTap: onSavedPlacesTap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildCard(
                icon: Icons.map_outlined,
                iconBg: AppColors.secondaryFixed,
                iconColor: AppColors.secondary,
                title: 'Lịch trình của tôi',
                subtitle: tripsSummary,
                onTap: onMyTripsTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildCard(
                icon: Icons.tune,
                iconBg: AppColors.tertiaryFixed,
                iconColor: AppColors.tertiary,
                title: 'Sở thích du lịch',
                subtitle: preferencesSummary,
                onTap: onPreferencesTap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildCard(
                icon: Icons.forum_outlined,
                iconBg: AppColors.primaryFixedDim,
                iconColor: AppColors.onPrimaryFixed,
                title: 'Trợ lý AI',
                subtitle: 'Hỏi đáp & Kế hoạch',
                onTap: onAiAssistantTap,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 124,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceContainerLow, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(15, 23, 42, 0.04),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon & Trailing Chevron
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.outline,
                  ),
                ],
              ),

              // Title & Subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.labelLg.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySm.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
