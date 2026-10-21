import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';

/// TravelSense Floating Glassmorphic Bottom Navigation Bar.
/// Features an elevated gradient AI button in the center and 4 tab destinations.
class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 68,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Glassmorphic Dock Container
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest.withValues(
                        alpha: 0.92,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.2,
                      ),

                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(15, 23, 42, 0.12),
                          blurRadius: 32,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(
                          0,
                          Icons.home_outlined,
                          Icons.home,
                          'Home',
                        ),
                        _buildNavItem(
                          1,
                          Icons.explore_outlined,
                          Icons.explore,
                          'Explore',
                        ),
                        // Spacer for elevated AI button
                        const SizedBox(width: 52),
                        _buildNavItem(
                          3,
                          Icons.luggage_outlined,
                          Icons.luggage,
                          'Trips',
                        ),
                        _buildNavItem(
                          4,
                          Icons.person_outline,
                          Icons.person,
                          'Profile',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Elevated Floating AI Button
              Positioned(top: -12, child: _buildElevatedAiButton(2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData outlineIcon,
    IconData filledIcon,
    String label,
  ) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? filledIcon : outlineIcon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            if (isSelected)
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildElevatedAiButton(int index) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondaryContainer],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2.5)
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.8),
                  width: 1.5,
                ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.40),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
      ),
    );
  }
}
