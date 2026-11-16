import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/audio/lip_sync_frame.dart';
import '../providers/voice_assistant_provider.dart';
import 'linh_lip_sync_avatar.dart';

/// 2D AI Tour Guide Avatar for TravelWise.
///
/// Features:
/// - Real-time 60fps GPU mesh deformation & lip sync from portrait image (`assets/images/hdv.png`)
/// - Studio stage lighting background matching the 3D avatar viewport
/// - Reactive voice-state ambient glow (Idle, Listening, Thinking, Speaking)
/// - Integrated with Blaze TTS audio stream & Vietnamese phonetic timeline fallback
/// - 100% offline, zero network requests, cross-platform on Flutter Web & Android!
class Ai2dAvatar extends StatefulWidget {
  final VoiceState voiceState;
  final ValueListenable<LipSyncFrame>? lipSyncListenable;
  final String speechText;
  final String imagePath;
  final Alignment alignment;
  final double ttsSpeed;

  const Ai2dAvatar({
    super.key,
    required this.voiceState,
    this.lipSyncListenable,
    this.speechText = '',
    this.imagePath = 'assets/images/hdv.png',
    this.alignment = const Alignment(0, -0.65),
    this.ttsSpeed = 1.5,
  });

  @override
  State<Ai2dAvatar> createState() => _Ai2dAvatarState();
}

class _Ai2dAvatarState extends State<Ai2dAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Studio Lighting Background (Matches 3D Studio lighting)
          _buildStudioBackground(context, widget.voiceState),

          // 2. Audio-reactive Animated Aura Halo
          _buildAuraGlow(widget.voiceState),

          // 3. Core 2D Lip-Sync & Face Rig
          LinhLipSyncAvatar(
            voiceState: widget.voiceState,
            speechText: widget.speechText,
            lipSyncListenable: widget.lipSyncListenable,
            alignment: widget.alignment,
            imagePath: widget.imagePath,
            ttsSpeed: widget.ttsSpeed,
          ),

          // 4. Subtle Vignette & Soft Floor Touch
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      const Color(0xFFF6F8FB).withValues(alpha: 0.35),
                    ],
                    stops: const [0.0, 0.88, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioBackground(BuildContext context, VoiceState state) {
    Color ambientGlow;
    Color outerGlow;
    switch (state) {
      case VoiceState.speaking:
        ambientGlow = const Color(0xFF38BDF8).withValues(alpha: 0.28);
        outerGlow = const Color(0xFFBAE6FD).withValues(alpha: 0.20);
        break;
      case VoiceState.listening:
        ambientGlow = const Color(0xFF10B981).withValues(alpha: 0.25);
        outerGlow = const Color(0xFFA7F3D0).withValues(alpha: 0.18);
        break;
      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        ambientGlow = const Color(0xFF14B8A6).withValues(alpha: 0.26);
        outerGlow = const Color(0xFF99F6E4).withValues(alpha: 0.18);
        break;
      case VoiceState.error:
        ambientGlow = const Color(0xFFEF4444).withValues(alpha: 0.22);
        outerGlow = const Color(0xFFFECACA).withValues(alpha: 0.15);
        break;
      case VoiceState.idle:
        ambientGlow = const Color(0xFF6366F1).withValues(alpha: 0.18);
        outerGlow = const Color(0xFFE0E7FF).withValues(alpha: 0.15);
        break;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFE8F1FC),
            Color(0xFFF1F5F9),
            Color(0xFFF8FAFC),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.22),
                radius: 0.75,
                colors: [
                  ambientGlow,
                  outerGlow,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuraGlow(VoiceState state) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        Color glowColor;
        double radius;
        double opacity;

        switch (state) {
          case VoiceState.speaking:
            glowColor = const Color(0xFF0284C7);
            radius = 0.55 + 0.15 * pulse;
            opacity = 0.18 + 0.10 * pulse;
            break;
          case VoiceState.listening:
            glowColor = const Color(0xFF10B981);
            radius = 0.50 + 0.12 * math.sin(pulse * math.pi);
            opacity = 0.15 + 0.12 * pulse;
            break;
          case VoiceState.thinking:
          case VoiceState.processing:
          case VoiceState.connecting:
            glowColor = const Color(0xFF0D9488);
            radius = 0.45 + 0.10 * pulse;
            opacity = 0.15 + 0.08 * pulse;
            break;
          case VoiceState.error:
            glowColor = const Color(0xFFEF4444);
            radius = 0.45;
            opacity = 0.10;
            break;
          case VoiceState.idle:
            glowColor = const Color(0xFF6366F1);
            radius = 0.42 + 0.05 * pulse;
            opacity = 0.08 + 0.04 * pulse;
            break;
        }

        return IgnorePointer(
          child: Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    glowColor.withValues(alpha: opacity),
                    glowColor.withValues(alpha: opacity * 0.4),
                    Colors.transparent,
                  ],
                  stops: [0.0, radius, 1.0],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

