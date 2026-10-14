import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/map_provider.dart';
import '../../data/services/location_service.dart';

/// Full-screen overlay shown when location permission is not yet granted.
class LocationPermissionOverlay extends ConsumerWidget {
  const LocationPermissionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mapProvider);
    final notifier = ref.read(mapProvider.notifier);
    final status = state.permissionStatus;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Animated icon ──────────────────────────────────────────────
              _AnimatedGlobeIcon(status: status),

              const SizedBox(height: AppSpacing.xl),

              // ── Title ──────────────────────────────────────────────────────
              Text(
                _getTitle(status),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Description ────────────────────────────────────────────────
              Text(
                _getDescription(status),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),

              // ── Extra hint for permanently denied ─────────────────────────
              if (status == LocationPermissionStatus.permanentlyDenied) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                        color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chrome: Nhấn biểu tượng 🔒 trên thanh địa chỉ → '
                          'Site settings → Location → Allow',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFB45309),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),

              // ── Primary button ────────────────────────────────────────────
              if (status != LocationPermissionStatus.requesting)
                _PrimaryButton(
                  label: _getPrimaryLabel(status),
                  onTap: () => notifier.requestLocationPermission(),
                  isLoading: false,
                ),

              if (status == LocationPermissionStatus.requesting)
                const _PrimaryButton(label: '...', onTap: null, isLoading: true),

              const SizedBox(height: AppSpacing.md),

              // ── Secondary button ───────────────────────────────────────────
              TextButton(
                onPressed: notifier.skipPermission,
                child: const Text(
                  'Để sau',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle(LocationPermissionStatus status) {
    switch (status) {
      case LocationPermissionStatus.denied:
        return 'Quyền vị trí bị từ chối';
      case LocationPermissionStatus.permanentlyDenied:
        return 'Quyền bị chặn trong trình duyệt';
      case LocationPermissionStatus.serviceDisabled:
        return 'GPS đang tắt';
      default:
        return 'Khám phá vị trí của bạn';
    }
  }

  String _getDescription(LocationPermissionStatus status) {
    switch (status) {
      case LocationPermissionStatus.denied:
        return 'Bạn đã từ chối quyền vị trí. Nhấn "Thử lại" để cấp quyền.';
      case LocationPermissionStatus.permanentlyDenied:
        return 'Trình duyệt đã chặn quyền vị trí. '
            'Vui lòng cấp lại quyền trong cài đặt trình duyệt.';
      case LocationPermissionStatus.serviceDisabled:
        return 'Dịch vụ vị trí đang tắt trên thiết bị của bạn. '
            'Vui lòng bật GPS và thử lại.';
      default:
        return 'Cho phép TravelWise sử dụng vị trí để hiển thị vị trí hiện tại '
            'của bạn trên bản đồ và hỗ trợ khám phá các địa điểm gần đó.';
    }
  }

  String _getPrimaryLabel(LocationPermissionStatus status) {
    switch (status) {
      case LocationPermissionStatus.denied:
      case LocationPermissionStatus.serviceDisabled:
        return 'Thử lại';
      case LocationPermissionStatus.permanentlyDenied:
        return 'Mở hướng dẫn';
      default:
        return 'Cho phép truy cập';
    }
  }
}

class _AnimatedGlobeIcon extends StatefulWidget {
  final LocationPermissionStatus status;
  const _AnimatedGlobeIcon({required this.status});

  @override
  State<_AnimatedGlobeIcon> createState() => _AnimatedGlobeIconState();
}

class _AnimatedGlobeIconState extends State<_AnimatedGlobeIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.status == LocationPermissionStatus.denied ||
        widget.status == LocationPermissionStatus.permanentlyDenied ||
        widget.status == LocationPermissionStatus.serviceDisabled;

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isError
                ? [
                    AppColors.warning.withOpacity(0.8),
                    AppColors.warning,
                  ]
                : [
                    AppColors.primary,
                    AppColors.secondary,
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (isError ? AppColors.warning : AppColors.primary)
                  .withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          isError ? Icons.location_off_rounded : Icons.location_on_rounded,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: isLoading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    );
  }
}

