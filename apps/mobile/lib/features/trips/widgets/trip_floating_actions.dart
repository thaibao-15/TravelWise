import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';

class TripFloatingActions extends StatelessWidget {
  const TripFloatingActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(LucideIcons.map, size: 20),
            label: const Text('Xem lộ trình bản đồ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
