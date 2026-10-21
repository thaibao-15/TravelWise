import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

/// Section A: Profile Header with branding, title, quick settings & QR buttons.
class ProfileHeader extends StatelessWidget {
  final VoidCallback onSettingsTap;
  final VoidCallback onQrTap;

  const ProfileHeader({
    super.key,
    required this.onSettingsTap,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Title Group
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TÀI KHOẢN TRAVELSENSE',
                style: AppTextStyles.labelSm.copyWith(
                  letterSpacing: 1.2,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text('Hồ sơ cá nhân', style: AppTextStyles.headlineLgMobile),
            ],
          ),
        ),

        // Right Action Buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCircularButton(
              icon: Icons.settings,
              tooltip: 'Cài đặt nhanh',
              onTap: onSettingsTap,
            ),
            const SizedBox(width: 8),
            _buildCircularButton(
              icon: Icons.qr_code_2,
              tooltip: 'Mã QR chia sẻ',
              onTap: onQrTap,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceContainerLow,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: AppColors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
