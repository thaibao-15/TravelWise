import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class HeaderBar extends StatelessWidget {
  const HeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.menu, color: AppColors.textPrimary),
          Row(
            children: const [
              Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: AppSpacing.sm),
              Text('Đà Nẵng, VN', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(width: AppSpacing.xs),
              Icon(Icons.keyboard_arrow_down, color: AppColors.textPrimary),
            ],
          ),
          Row(
            children: const [
              Icon(Icons.notifications_none, color: AppColors.textPrimary),
              SizedBox(width: AppSpacing.md),
              CircleAvatar(
                radius: 16,
                backgroundImage: NetworkImage('https://i.pravatar.cc/100'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
