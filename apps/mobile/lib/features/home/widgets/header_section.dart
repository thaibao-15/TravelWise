import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';

class HeaderSection extends StatelessWidget {
  const HeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Text('Chào buổi sáng', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  SizedBox(width: 4),
                  Text('👋', style: TextStyle(fontSize: 14)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Linh Nguyễn', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(
                children: const [
                  Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text('Đà Nẵng, Việt Nam', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  Icon(Icons.keyboard_arrow_down, size: 16),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.wb_sunny_outlined, size: 14, color: Colors.orange),
                        SizedBox(width: 4),
                        Text('29°C Nắng nhẹ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.notifications_none, color: AppColors.textPrimary),
                  const SizedBox(width: AppSpacing.md),
                  const CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage('https://i.pravatar.cc/100'),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }
}
