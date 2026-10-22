import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../auth/domain/entities/user.dart';

/// Section B: User Identity Card with avatar, camera trigger, real user details,
/// verified badge, membership tier, and edit/share actions.
class ProfileIdentityCard extends StatelessWidget {
  final User user;
  final String membershipTier;
  final VoidCallback onEditTap;
  final VoidCallback onShareTap;
  final VoidCallback onCameraTap;

  const ProfileIdentityCard({
    super.key,
    required this.user,
    required this.membershipTier,
    required this.onEditTap,
    required this.onShareTap,
    required this.onCameraTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.fullName.trim().isNotEmpty
        ? user.fullName
        : 'Du khách TravelSense';
    final joinedYear = user.createdAt.year;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Top-Right Ambient Blur Accent
            Positioned(
              top: -24,
              right: -24,
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondaryFixed.withValues(alpha: 0.4),
                ),
              ),
            ),

            // Card Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar & Info Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar with Camera Overlay
                      _buildAvatarWithBadge(),
                      const SizedBox(width: 16),

                      // User Credentials
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name & Verified Badge
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: AppTextStyles.headlineMd,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (user.isActive) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),

                            // Email & Joined year
                            Text(
                              '${user.email} · Kể từ $joinedYear',
                              style: AppTextStyles.bodySm,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 8),

                            // Membership Tier Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.secondaryFixed,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.travel_explore,
                                    size: 13,
                                    color: AppColors.secondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    membershipTier,
                                    style: AppTextStyles.labelSm.copyWith(
                                      color: AppColors.onSecondaryFixed,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Quick Action Buttons Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.edit_outlined,
                          label: 'Chỉnh sửa',
                          isPrimary: true,
                          onTap: onEditTap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.share_outlined,
                          label: 'Chia sẻ hồ sơ',
                          isPrimary: false,
                          onTap: onShareTap,
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
    );
  }

  Widget _buildAvatarWithBadge() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Circular Avatar
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceContainer,
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.08),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                ? Image.network(
                    user.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stackTrace) =>
                        _buildAvatarPlaceholder(),
                  )
                : _buildAvatarPlaceholder(),
          ),
        ),

        // Camera Badge Button
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onCameraTap,
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  Icons.photo_camera,
                  size: 15,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarPlaceholder() {
    final initials = user.fullName.isNotEmpty
        ? user.fullName.trim().split(' ').map((e) => e[0]).take(2).join()
        : 'U';
    return Container(
      color: AppColors.primaryFixed,
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: AppTextStyles.headlineMd.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary
                    ? AppColors.onSurface
                    : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.labelMd.copyWith(
                    color: isPrimary
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
