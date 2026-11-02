import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

/// Visually clear blue user location marker indicator with a subtle pulsing background.
class CurrentLocationMarker extends StatefulWidget {
  final double size;

  const CurrentLocationMarker({super.key, this.size = 44.0});

  @override
  State<CurrentLocationMarker> createState() => _CurrentLocationMarkerState();
}

class _CurrentLocationMarkerState extends State<CurrentLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseScale = Tween<double>(
      begin: 0.9,
      end: 1.45,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutQuad));

    _pulseOpacity = Tween<double>(
      begin: 0.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutQuad));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Pulsing outer ripple ───────────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) {
              return Opacity(
                opacity: _pulseOpacity.value,
                child: Transform.scale(
                  scale: _pulseScale.value,
                  child: Container(
                    width: widget.size * 0.85,
                    height: widget.size * 0.85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Outer white boundary & shadow ─────────────────────────────────
          Container(
            width: widget.size * 0.55,
            height: widget.size * 0.55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),

          // ── Core blue dot ─────────────────────────────────────────────────
          Container(
            width: widget.size * 0.42,
            height: widget.size * 0.42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Container(
                width: widget.size * 0.14,
                height: widget.size * 0.14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
