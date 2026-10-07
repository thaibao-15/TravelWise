import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../providers/voice_assistant_provider.dart';
import 'waveform.dart';

/// The central animated Voice Orb — native Flutter only, no images/video.
/// Outer glow → ripple rings → gradient ring → dark inner circle → waveform.
class VoiceOrb extends StatefulWidget {
  final VoiceState voiceState;
  final VoidCallback onTap;

  const VoiceOrb({
    super.key,
    required this.voiceState,
    required this.onTap,
  });

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late AnimationController _glowController;
  late AnimationController _tapController;
  late Animation<double> _tapScale;

  @override
  void initState() {
    super.initState();

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );

    _tapScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.94), weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 0.94, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _tapController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _glowController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  Color get _primaryColor {
    switch (widget.voiceState) {
      case VoiceState.listening:
        return AppColors.primary;
      case VoiceState.thinking:
        return AppColors.secondary;
      case VoiceState.speaking:
        return AppColors.success;
    }
  }

  void _handleTap() {
    _tapController.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _tapScale,
        child: SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Outer soft glow ──────────────────────────────────────────
              AnimatedBuilder(
                animation: _glowController,
                builder: (_, __) {
                  final opacity = 0.08 + _glowController.value * 0.10;
                  return Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _primaryColor.withOpacity(opacity),
                          blurRadius: 48,
                          spreadRadius: 12,
                        ),
                      ],
                    ),
                  );
                },
              ),

              // ── Ripple ring 1 ─────────────────────────────────────────────
              AnimatedBuilder(
                animation: _rippleController,
                builder: (_, __) {
                  final t = _rippleController.value;
                  final size = 130 + t * 60.0;
                  return Opacity(
                    opacity: (1 - t) * 0.22,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _primaryColor, width: 1.5),
                      ),
                    ),
                  );
                },
              ),

              // ── Ripple ring 2 (offset phase) ──────────────────────────────
              AnimatedBuilder(
                animation: _rippleController,
                builder: (_, __) {
                  final t = (_rippleController.value + 0.5) % 1.0;
                  final size = 130 + t * 60.0;
                  return Opacity(
                    opacity: (1 - t) * 0.15,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _primaryColor, width: 1.0),
                      ),
                    ),
                  );
                },
              ),

              // ── Gradient ring ─────────────────────────────────────────────
              AnimatedBuilder(
                animation: _glowController,
                builder: (_, __) {
                  final angle =
                      _glowController.value * 2 * math.pi;
                  return Container(
                    width: 138,
                    height: 138,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        startAngle: angle,
                        endAngle: angle + 2 * math.pi,
                        colors: [
                          _primaryColor,
                          AppColors.secondary,
                          _primaryColor.withOpacity(0.5),
                          _primaryColor,
                        ],
                      ),
                    ),
                  );
                },
              ),

              // ── Inner dark orb ────────────────────────────────────────────
              Container(
                width: 126,
                height: 126,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.orbDark,
                      const Color(0xFF0F1E2E),
                    ],
                    center: Alignment.center,
                    radius: 1.0,
                  ),
                ),
                child: Center(
                  child: WaveformBars(
                    voiceState: widget.voiceState,
                    barWidth: 4.5,
                    maxBarHeight: 38,
                    barColor: Colors.white.withOpacity(0.92),
                  ),
                ),
              ),

              // ── State label (micro text at bottom of orb) ─────────────────
              Positioned(
                bottom: 28,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    switch (widget.voiceState) {
                      VoiceState.listening => '● Đang nghe',
                      VoiceState.thinking => '◌ Đang xử lý',
                      VoiceState.speaking => '▷ Đang nói',
                    },
                    key: ValueKey(widget.voiceState),
                    style: TextStyle(
                      color: _primaryColor.withOpacity(0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
