import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../providers/voice_assistant_provider.dart';

/// Animated 7-bar waveform displayed inside the Voice Orb.
/// Uses a single AnimationController — no Timer, properly disposed.
class WaveformBars extends StatefulWidget {
  final VoiceState voiceState;
  final Color barColor;
  final double barWidth;
  final double maxBarHeight;

  const WaveformBars({
    super.key,
    required this.voiceState,
    this.barColor = Colors.white,
    this.barWidth = 4,
    this.maxBarHeight = 36,
  });

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Phase offsets for each bar so they animate at different phases
  final List<double> _phaseOffsets = [0.0, 0.8, 1.6, 0.4, 1.2, 2.0, 0.6];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _updateSpeed();
  }

  @override
  void didUpdateWidget(WaveformBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceState != widget.voiceState) {
      _updateSpeed();
    }
  }

  void _updateSpeed() {
    switch (widget.voiceState) {
      case VoiceState.listening:
        _controller.duration = const Duration(milliseconds: 1200);
      case VoiceState.thinking:
        _controller.duration = const Duration(milliseconds: 2200);
      case VoiceState.speaking:
        _controller.duration = const Duration(milliseconds: 700);
    }
    _controller.repeat();
  }

  double _barHeight(int index, double animValue) {
    final phase = _phaseOffsets[index];
    final raw = (math.sin(animValue * 2 * math.pi + phase) + 1) / 2;

    final minH = widget.maxBarHeight * 0.18;
    final maxH = widget.maxBarHeight;

    switch (widget.voiceState) {
      case VoiceState.listening:
        return minH + raw * (maxH * 0.65 - minH);
      case VoiceState.thinking:
        // Subtle, slow
        return minH + raw * (maxH * 0.35 - minH);
      case VoiceState.speaking:
        // Energetic, full range
        return minH + raw * (maxH - minH);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(7, (i) {
            final h = _barHeight(i, _controller.value);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.barWidth * 0.4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                width: widget.barWidth,
                height: h,
                decoration: BoxDecoration(
                  color: widget.barColor,
                  borderRadius:
                      BorderRadius.circular(widget.barWidth / 2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
