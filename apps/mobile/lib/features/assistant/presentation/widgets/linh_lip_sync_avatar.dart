import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/audio/lip_sync_frame.dart';
import '../../../../core/constants/colors.dart';
import '../providers/voice_assistant_provider.dart';

/// Photorealistic 60fps audio-driven 2D lip-sync & micro-expression rig
/// for the Linh AI portrait (`assets/images/linh_ai.jpg`, 896x1200).
///
/// Combines:
/// 1. Real-time audio formant/amplitude values from [lipSyncListenable]
///    (Web Audio `AnalyserNode` at 60fps when speaking on Web).
/// 2. Vietnamese phonetic syllable envelope fallback when audio playback does
///    not expose raw PCM (e.g. Web Speech fallback or native platforms).
/// 3. GPU triangle-mesh deformation (`Canvas.drawVertices`) with an anatomical
///    split seam between upper teeth and lower lip so the mandible drops
///    naturally without stretching the upper teeth, plus consonant closure
///    overlap (`M/B/P`), natural blinking, and subtle breathing motion.
class LinhLipSyncAvatar extends StatefulWidget {
  final VoiceState voiceState;
  final String speechText;
  final ValueListenable<LipSyncFrame>? lipSyncListenable;
  final Alignment alignment;

  const LinhLipSyncAvatar({
    super.key,
    required this.voiceState,
    required this.speechText,
    this.lipSyncListenable,
    this.alignment = const Alignment(0, -0.2),
  });

  @override
  State<LinhLipSyncAvatar> createState() => _LinhLipSyncAvatarState();
}

class _LinhLipSyncAvatarState extends State<LinhLipSyncAvatar>
    with SingleTickerProviderStateMixin {
  static ui.Image? _cachedPortrait;
  static Future<ui.Image?>? _loadingFuture;

  ui.Image? _portrait;
  late final Ticker _ticker;
  final AvatarRigState _rig = AvatarRigState();

  Duration _lastTick = Duration.zero;
  double _elapsedSec = 0.0;
  double _speakingElapsedSec = 0.0;
  double _nextBlinkAtSec = 2.6;
  double _blinkStartSec = -10.0;
  final math.Random _rng = math.Random(42);

  List<_PhoneticBeat> _phoneticBeats = const [];
  String _cachedSpeechText = '';

  @override
  void initState() {
    super.initState();
    _portrait = _cachedPortrait;
    if (_portrait == null) {
      _loadPortrait();
    }
    _syncPhoneticBeats();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadPortrait() async {
    _loadingFuture ??= _decodeAssetPortrait();
    final loaded = await _loadingFuture;
    if (mounted && loaded != null) {
      setState(() {
        _portrait = loaded;
      });
    }
  }

  static Future<ui.Image?> _decodeAssetPortrait() async {
    try {
      final data = await rootBundle.load('assets/images/linh_ai.jpg');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cachedPortrait = frame.image;
      return frame.image;
    } catch (_) {
      _loadingFuture = null;
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant LinhLipSyncAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speechText != _cachedSpeechText) {
      _syncPhoneticBeats();
    }
    if (widget.voiceState == VoiceState.speaking &&
        oldWidget.voiceState != VoiceState.speaking) {
      _speakingElapsedSec = 0.0;
    }
  }

  void _syncPhoneticBeats() {
    _cachedSpeechText = widget.speechText;
    _phoneticBeats = _VietnamesePhoneticTimeline.build(widget.speechText);
    _speakingElapsedSec = 0.0;
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? (1.0 / 60.0)
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.001, 0.05);
    _lastTick = elapsed;
    _elapsedSec += dt;

    // 1. Natural periodic eye blink (135ms close-open cycle every 3.2..5.8s)
    if (_elapsedSec >= _nextBlinkAtSec) {
      _blinkStartSec = _elapsedSec;
      // Occasional natural double-blink (15% probability)
      if (_rng.nextDouble() < 0.15) {
        _nextBlinkAtSec = _elapsedSec + 0.28;
      } else {
        _nextBlinkAtSec = _elapsedSec + 3.2 + _rng.nextDouble() * 2.6;
      }
    }
    double blink = 0.0;
    final blinkAge = _elapsedSec - _blinkStartSec;
    if (blinkAge >= 0.0 && blinkAge < 0.145) {
      // Fast close (55ms), smooth open (90ms)
      blink = blinkAge < 0.055
          ? (blinkAge / 0.055)
          : (1.0 - (blinkAge - 0.055) / 0.090);
      blink = blink.clamp(0.0, 1.0);
    }

    // 2. Target mouth shape from real-time JS audio analyser or phonetic timeline
    final isSpeaking = widget.voiceState == VoiceState.speaking;
    final externalFrame = widget.lipSyncListenable?.value;

    double targetOpen = LipSyncFrame.restOpen;
    double targetWide = 0.0;
    double targetEnergy = 0.0;

    if (isSpeaking) {
      _speakingElapsedSec += dt;
      if (externalFrame != null && externalFrame.active) {
        targetOpen = externalFrame.mouthOpen;
        targetWide = externalFrame.mouthWide;
        targetEnergy = externalFrame.energy;
      } else {
        final synth = _VietnamesePhoneticTimeline.sample(
          _phoneticBeats,
          _speakingElapsedSec,
        );
        targetOpen = synth.mouthOpen;
        targetWide = synth.mouthWide;
        targetEnergy = synth.energy;
      }
    } else if (widget.voiceState == VoiceState.listening) {
      // Attentive warm smile while listening to user
      targetOpen = 0.25 + 0.02 * math.sin(_elapsedSec * 2.2);
      targetWide = 0.12;
      targetEnergy = 0.0;
    } else {
      _speakingElapsedSec = 0.0;
      targetOpen = LipSyncFrame.restOpen;
      targetWide = 0.0;
      targetEnergy = 0.0;
    }

    // Asymmetric smoothing: crisp syllable attack (~28ms), natural jaw release (~75ms)
    final openRate = targetOpen > _rig.mouthOpen ? 28.0 : 14.0;
    final openAlpha = (1.0 - math.exp(-openRate * dt)).clamp(0.0, 1.0);
    final wideAlpha = (1.0 - math.exp(-16.0 * dt)).clamp(0.0, 1.0);
    final energyAlpha = (1.0 - math.exp(-18.0 * dt)).clamp(0.0, 1.0);

    _rig.update(
      mouthOpen: _rig.mouthOpen + (targetOpen - _rig.mouthOpen) * openAlpha,
      mouthWide: _rig.mouthWide + (targetWide - _rig.mouthWide) * wideAlpha,
      energy: _rig.energy + (targetEnergy - _rig.energy) * energyAlpha,
      blink: blink,
      breathPhase: _elapsedSec * 1.45,
      nodPhase: _elapsedSec * 5.2,
      isSpeaking: isSpeaking,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _portrait;
    if (img == null) {
      return Image.asset(
        'assets/images/linh_ai.jpg',
        fit: BoxFit.cover,
        cacheWidth: 640,
        alignment: widget.alignment,
        errorBuilder: (ctx, err, stack) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.support_agent_rounded,
              size: 90,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: LinhPortraitRigPainter(
          image: img,
          rig: _rig,
          alignment: widget.alignment,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Mutable 60fps rig notifier that repaints [LinhPortraitRigPainter] directly
/// on the GPU without rebuilding the surrounding widget tree.
@visibleForTesting
class AvatarRigState extends ChangeNotifier {
  double mouthOpen = LipSyncFrame.restOpen;
  double mouthWide = 0.0;
  double energy = 0.0;
  double blink = 0.0;
  double breathPhase = 0.0;
  double nodPhase = 0.0;
  bool isSpeaking = false;

  void update({
    required double mouthOpen,
    required double mouthWide,
    required double energy,
    required double blink,
    required double breathPhase,
    required double nodPhase,
    required bool isSpeaking,
  }) {
    final changed =
        (this.mouthOpen - mouthOpen).abs() > 0.0015 ||
        (this.mouthWide - mouthWide).abs() > 0.002 ||
        (this.blink - blink).abs() > 0.005 ||
        (this.breathPhase - breathPhase).abs() > 0.015 ||
        this.isSpeaking != isSpeaking;
    this.mouthOpen = mouthOpen;
    this.mouthWide = mouthWide;
    this.energy = energy;
    this.blink = blink;
    this.breathPhase = breathPhase;
    this.nodPhase = nodPhase;
    this.isSpeaking = isSpeaking;
    if (changed) {
      notifyListeners();
    }
  }
}

/// Exposes mesh painting for both runtime rendering and visual verification tests.
@visibleForTesting
class LinhPortraitRigPainter extends CustomPainter {
  final ui.Image image;
  final AvatarRigState? _rig;
  final Alignment alignment;

  // Optional static overrides for deterministic golden/preview rendering
  final double? debugMouthOpen;
  final double? debugMouthWide;
  final double? debugBlink;
  final double? debugEnergy;

  LinhPortraitRigPainter({
    required this.image,
    AvatarRigState? rig,
    this.alignment = const Alignment(0, -0.2),
    this.debugMouthOpen,
    this.debugMouthWide,
    this.debugBlink,
    this.debugEnergy,
  }) : _rig = rig,
       super(repaint: rig);

  // Calibrated pixel landmarks on `assets/images/linh_ai.jpg` (896 x 1200)
  static const double _imgW = 896.0;
  static const double _imgH = 1200.0;

  static const List<double> _cols = <double>[
    0.0,
    260.0,
    360.0,
    410.0,
    435.0,
    452.0, // col 5: left mouth corner
    466.0, // col 6
    481.0, // col 7
    496.0, // col 8: mouth & chin center
    511.0, // col 9
    526.0, // col 10
    540.0, // col 11: right mouth corner
    568.0,
    600.0,
    660.0,
    896.0,
  ];

  static const int _numCols = 16;
  static const int _numRows = 18; // rows 0..8, 9 (9U), 10 (9L), 11..17

  static final Float32List _restUV = _buildRestUV();
  static final Uint16List _triangleIndices = _buildIndices();

  static double _rowRestY(int r, int c) {
    final x = _cols[c];
    switch (r) {
      case 0:
        return 0.0;
      case 1:
        return 280.0;
      case 2:
        return 453.5; // Sub-brow anchor (locks eyebrows 100% motionless!)
      case 3:
        // Upper eyelash margin (follows slight natural 2° head tilt)
        return 464.5 + ((x - 456.0) / 90.0).clamp(0.0, 1.0) * 4.2;
      case 4:
        // Lower eyelid margin
        return 479.0 + ((x - 456.0) / 90.0).clamp(0.0, 1.0) * 4.0;
      case 5:
        return 510.0; // Mid-nose anchor
      case 6:
        return 533.0; // Sub-nasal anchor
      case 7:
        // Top of upper lip (cupid's bow)
        if (c >= 5 && c <= 11) {
          const bow = <double>[548.0, 545.5, 544.5, 545.0, 545.0, 546.5, 551.0];
          return bow[c - 5];
        }
        return x < 496.0 ? 548.0 : 551.0;
      case 8:
        // Inner edge of upper lip / top of upper teeth
        if (c >= 5 && c <= 11) {
          const innerUp = <double>[
            550.0,
            550.2,
            551.0,
            551.8,
            552.0,
            552.8,
            554.0,
          ];
          return innerUp[c - 5];
        }
        return x < 496.0 ? 550.0 : 554.0;
      case 9: // Upper mouth seam (bottom edge of upper teeth)
        if (c >= 5 && c <= 11) {
          const seamUp = <double>[
            550.0, // col 5 (452): left corner (shared exact coord with row 10)
            558.0, // col 6 (466)
            563.0, // col 7 (481)
            564.8, // col 8 (496): bottom edge of central incisors
            563.5, // col 9 (511)
            559.0, // col 10 (526)
            554.0, // col 11 (540): right corner (shared exact coord with row 10)
          ];
          return seamUp[c - 5];
        }
        return x < 496.0 ? 550.0 : 554.0;
      case 10: // Lower mouth seam (top vermilion border of lower lip, below teeth)
        if (c >= 5 && c <= 11) {
          const seamLow = <double>[
            550.0, // col 5 (452): left corner (pinned to row 9!)
            559.4, // col 6 (466)
            564.8, // col 7 (481)
            566.8, // col 8 (496): pure pink lower lip, zero white tooth pixel!
            565.3, // col 9 (511)
            560.6, // col 10 (526)
            554.0, // col 11 (540): right corner (pinned to row 9!)
          ];
          return seamLow[c - 5];
        }
        return x < 496.0 ? 550.0 : 554.0;
      case 11:
        // Bottom edge of lower lip
        if (c >= 5 && c <= 11) {
          const lowBot = <double>[
            554.0,
            567.5,
            574.5,
            577.5,
            575.5,
            569.5,
            558.0,
          ];
          return lowBot[c - 5];
        }
        return 568.0;
      case 12:
        return 595.0; // Mentolabial sulcus / upper chin
      case 13:
        return 620.0; // Chin tip contour
      case 14:
        return 665.0; // Upper neck shadow
      case 15:
        return 760.0; // Scarf / collarbone
      case 16:
        return 980.0; // Blazer / chest
      case 17:
      default:
        return 1200.0;
    }
  }

  static Float32List _buildRestUV() {
    final uv = Float32List(_numRows * _numCols * 2);
    int k = 0;
    for (int r = 0; r < _numRows; r++) {
      for (int c = 0; c < _numCols; c++) {
        uv[k++] = _cols[c];
        uv[k++] = _rowRestY(r, c);
      }
    }
    return uv;
  }

  static Uint16List _buildIndices() {
    // Emit upper rows (0..9, skipping gap 9->10) first, then lower rows (10..17)
    // so the lower lip naturally overlaps upper teeth during consonant closure!
    final indices = <int>[];
    void addBand(int rStart, int rEnd) {
      for (int r = rStart; r < rEnd; r++) {
        for (int c = 0; c < _numCols - 1; c++) {
          final i00 = r * _numCols + c;
          final i10 = i00 + 1;
          final i01 = (r + 1) * _numCols + c;
          final i11 = i01 + 1;
          indices
            ..add(i00)
            ..add(i10)
            ..add(i11)
            ..add(i00)
            ..add(i11)
            ..add(i01);
        }
      }
    }

    addBand(0, 9); // Crown -> Upper teeth bottom (`r9U`)
    addBand(10, _numRows - 1); // Lower lip top (`r9L`) -> Bottom border
    return Uint16List.fromList(indices);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final sx = image.width / _imgW;
    final sy = image.height / _imgH;

    // Compute exact BoxFit.cover + Alignment transform in logical 896x1200 space
    final scale = math.max(size.width / _imgW, size.height / _imgH);
    final scaledW = _imgW * scale;
    final scaledH = _imgH * scale;
    final dx = (size.width - scaledW) * (alignment.x + 1.0) * 0.5;
    final dy = (size.height - scaledH) * (alignment.y + 1.0) * 0.5;

    final open = (debugMouthOpen ?? _rig?.mouthOpen ?? LipSyncFrame.restOpen)
        .clamp(0.0, 1.0);
    final wide = (debugMouthWide ?? _rig?.mouthWide ?? 0.0).clamp(-1.0, 1.0);
    final blink = (debugBlink ?? _rig?.blink ?? 0.0).clamp(0.0, 1.0);
    final energy = (debugEnergy ?? _rig?.energy ?? 0.0).clamp(0.0, 1.0);
    final breathPhase = _rig?.breathPhase ?? 0.0;
    final nodPhase = _rig?.nodPhase ?? 0.0;
    final isSpeaking = _rig?.isSpeaking ?? (debugMouthOpen != null);

    // Signed jaw delta relative to neutral resting smile (`0.28`):
    // - Positive `[0 .. +1]`: vowel opening (mandible drops, revealing oral cavity)
    // - Negative `[-1 .. 0]`: bilabial/consonant closure (lips press over teeth)
    final double jawExpand = open >= LipSyncFrame.restOpen
        ? ((open - LipSyncFrame.restOpen) / (1.0 - LipSyncFrame.restOpen))
        : 0.0;
    final double lipClose = open < LipSyncFrame.restOpen
        ? ((LipSyncFrame.restOpen - open) / LipSyncFrame.restOpen)
        : 0.0;

    final breath = math.sin(breathPhase);
    final headNodY = isSpeaking
        ? (energy * 1.6 + 0.55 * math.sin(nodPhase) * energy)
        : (0.65 * breath);
    final headTiltX = isSpeaking
        ? (0.45 * math.cos(nodPhase * 0.6) * energy)
        : 0.0;

    final positions = Float32List(_numRows * _numCols * 2);
    final texCoords = Float32List(_numRows * _numCols * 2);

    for (int r = 0; r < _numRows; r++) {
      for (int c = 0; c < _numCols; c++) {
        final idx = (r * _numCols + c) * 2;
        final u = _restUV[idx];
        final v = _restUV[idx + 1];
        texCoords[idx] = u * sx;
        texCoords[idx + 1] = v * sy;

        double px = u;
        double py = v;

        // Keep outer frame borders 100% locked so ClipRRect never exposes gaps
        final isBorder =
            c == 0 || c == _numCols - 1 || r == 0 || r == _numRows - 1;
        if (!isBorder) {
          // 1. Subtle head micro-nod & breathing on head/shoulders
          if (r >= 2 && r <= 14 && c >= 2 && c <= 13) {
            final headWeight = (c >= 4 && c <= 12) ? 1.0 : 0.45;
            px += headTiltX * headWeight;
            py += headNodY * headWeight;
          } else if (r == 15 || r == 16) {
            final chestWeight = r == 15 ? 1.0 : 0.55;
            py += -1.8 * breath * chestWeight;
          }

          // 2. Natural eyelid blink (left eye center ~458, right eye center ~545)
          if (blink > 0.001 && (r == 3 || r == 4)) {
            final leftEyeW = math.exp(-math.pow((u - 458.0) / 21.0, 2));
            final rightEyeW = math.exp(-math.pow((u - 545.0) / 22.0, 2));
            final eyeW = math.max(leftEyeW, rightEyeW);
            if (r == 3) {
              py +=
                  13.0 * blink * eyeW; // Upper lash sweeps cleanly to lower lid
            } else {
              py -= 2.2 * blink * eyeW; // Lower lid rises slightly to meet it
            }
          }

          // 3. Horizontal mouth corner widening ('I/E/A') vs rounding ('O/U')
          if (r >= 7 && r <= 12 && c >= 4 && c <= 12) {
            final distFromMouthCenter = u - 496.0;
            final horizFalloff = math.exp(
              -math.pow(distFromMouthCenter.abs() / 54.0, 2),
            );
            // Keep r==9 and r==10 horizontal weights identical so corners never split!
            final rowW = (r >= 8 && r <= 11) ? 1.0 : 0.45;
            final spreadPx = wide * 3.8 - jawExpand * 1.1;
            px +=
                distFromMouthCenter.sign *
                (distFromMouthCenter.abs() / 44.0).clamp(0.0, 1.15) *
                spreadPx *
                horizFalloff *
                rowW;
          }

          // 4. Anatomical mouth profile across columns 5..11 (452..540)
          double mouthArc = 0.0;
          if (c > 5 && c < 11) {
            final t = (u - 452.0) / (540.0 - 452.0); // 0..1 across mouth
            mouthArc = math.sin(t * math.pi); // 0 at corners, 1.0 at center!
          }
          // Broader jaw/chin bell curve across columns 3..13 (410..600)
          final jawBell = math.exp(-math.pow((u - 496.0) / 56.0, 2));

          if (r == 7) {
            // Upper lip cupid's bow: subtle lift on loud vowels, slight drop on M/B/P
            py += (-1.4 * jawExpand + 4.0 * lipClose) * mouthArc;
          } else if (r == 8) {
            // Inner upper lip: drops down over top of teeth during M/B/P closure
            py += (-1.1 * jawExpand + 5.8 * lipClose) * mouthArc;
          } else if (r == 9) {
            // Upper teeth bottom (`r9U`): stays anchored to upper skull!
            py += (-0.6 * jawExpand + 1.5 * lipClose) * mouthArc;
          } else if (r == 10) {
            // Anchor rest position to `_rowRestY(9, c)` so seam is 100% closed at idle,
            // while UV samples pure lower-lip vermilion (`_rowRestY(10, c)`).
            final baseSeamY =
                _rowRestY(9, c) +
                ((r >= 2 && r <= 14 && c >= 2 && c <= 13)
                    ? headNodY * ((c >= 4 && c <= 12) ? 1.0 : 0.45)
                    : 0.0);
            py = baseSeamY + (16.5 * jawExpand - 10.6 * lipClose) * mouthArc;
          } else if (r == 11) {
            // Lower lip bottom: moves with lower lip, plumping slightly when rounded
            final plump = wide < 0 ? (-wide * 1.8 * jawExpand) : 0.0;
            py +=
                (15.2 * jawExpand + plump - 8.2 * lipClose) * mouthArc +
                2.0 * jawExpand * jawBell * (1.0 - mouthArc);
          } else if (r == 12) {
            // Upper chin / mentolabial fold
            py += (11.2 * jawExpand - 5.0 * lipClose) * jawBell;
          } else if (r == 13) {
            // Chin tip contour — realistic mandible drop!
            py += (8.6 * jawExpand - 3.5 * lipClose) * jawBell;
          } else if (r == 14) {
            // Soft under-chin / neck skin damping
            py += (2.4 * jawExpand - 0.8 * lipClose) * jawBell;
          }
        }

        positions[idx] = px;
        positions[idx + 1] = py;
      }
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    // A. Paint warm anatomical oral cavity + soft tongue behind the open seam.
    // Drawn unclipped behind the opaque photo mesh to avoid AA conflation seams!
    if (jawExpand > 0.008) {
      _paintOralCavity(canvas, positions, jawExpand, wide);
    }

    // B. Render hardware-accelerated textured triangle mesh
    final shaderMatrix = Float64List.fromList(<double>[
      1.0 / sx, 0.0, 0.0, 0.0, //
      0.0, 1.0 / sy, 0.0, 0.0, //
      0.0, 0.0, 1.0, 0.0, //
      0.0, 0.0, 0.0, 1.0, //
    ]);
    final meshPaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        shaderMatrix,
      );

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: _triangleIndices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, meshPaint);

    // C. Soft lip/teeth contact shading for seamless photorealistic blending
    _paintMouthContactShading(canvas, positions, jawExpand, lipClose);

    canvas.restore();
  }

  void _paintOralCavity(
    Canvas canvas,
    Float32List pos,
    double jawExpand,
    double wide,
  ) {
    Offset pt(int r, int c) {
      final i = (r * _numCols + c) * 2;
      return Offset(pos[i], pos[i + 1]);
    }

    final topCenter = pt(9, 8);
    final botCenter = pt(10, 8);
    final cavityRect = Rect.fromLTRB(
      pt(9, 5).dx - 6.0,
      math.min(pt(9, 5).dy, topCenter.dy) - 6.0,
      pt(9, 11).dx + 6.0,
      botCenter.dy + 8.0,
    );

    // 1. Deep warm oral shadow gradient (masked naturally by opaque photo mesh)
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(topCenter.dx, topCenter.dy - 1.0),
        Offset(botCenter.dx, botCenter.dy + 1.0),
        const <Color>[Color(0xFF1E070B), Color(0xFF381016), Color(0xFF521B23)],
        const <double>[0.0, 0.55, 1.0],
      );
    canvas.drawRect(cavityRect, bgPaint);

    // 2. Subtle organic tongue dome visible in lower half when mouth opens wide
    if (jawExpand > 0.16) {
      final openH = (botCenter.dy - topCenter.dy).clamp(1.0, 30.0);
      final tongueW = (34.0 + wide * 4.0).clamp(24.0, 42.0);
      final tongueRect = Rect.fromCenter(
        center: Offset(botCenter.dx, botCenter.dy - openH * 0.10),
        width: tongueW,
        height: openH * 0.90,
      );
      final tonguePaint = Paint()
        ..shader = ui.Gradient.radial(
          tongueRect.center.translate(0, -openH * 0.15),
          tongueW * 0.65,
          const <Color>[
            Color(0xFF96424C),
            Color(0xFF69252F),
            Color(0xFF381016),
          ],
          const <double>[0.0, 0.65, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      canvas.drawOval(tongueRect, tonguePaint);
    }
  }

  void _paintMouthContactShading(
    Canvas canvas,
    Float32List pos,
    double jawExpand,
    double lipClose,
  ) {
    Offset pt(int r, int c) {
      final i = (r * _numCols + c) * 2;
      return Offset(pos[i], pos[i + 1]);
    }

    if (jawExpand > 0.03) {
      // Soft feather along bottom edge of upper teeth & inner rim of lower lip
      final upperEdge = Path()..moveTo(pt(9, 5).dx, pt(9, 5).dy);
      final lowerEdge = Path()..moveTo(pt(10, 5).dx, pt(10, 5).dy);
      for (int c = 6; c <= 11; c++) {
        final pu = pt(9, c);
        final pl = pt(10, c);
        upperEdge.lineTo(pu.dx, pu.dy);
        lowerEdge.lineTo(pl.dx, pl.dy);
      }
      canvas.drawPath(
        upperEdge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(
            32,
            10,
            14,
            (0.42 * jawExpand).clamp(0.0, 0.38),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
      );
      canvas.drawPath(
        lowerEdge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(
            110,
            40,
            46,
            (0.55 * jawExpand).clamp(0.0, 0.45),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9),
      );
    } else if (lipClose > 0.22) {
      // Subtle natural lip-press line when lips meet on M / B / P consonants
      final pressAlpha = ((lipClose - 0.22) * 0.55).clamp(0.0, 0.42);
      final seamLine = Path()..moveTo(pt(10, 5).dx + 2.0, pt(10, 5).dy);
      for (int c = 6; c <= 11; c++) {
        final p = pt(10, c);
        seamLine.lineTo(p.dx - (c == 11 ? 2.0 : 0.0), p.dy);
      }
      canvas.drawPath(
        seamLine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(92, 36, 38, pressAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LinhPortraitRigPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.alignment != alignment ||
        oldDelegate.debugMouthOpen != debugMouthOpen ||
        oldDelegate.debugMouthWide != debugMouthWide ||
        oldDelegate.debugBlink != debugBlink;
  }
}

class _PhoneticBeat {
  final double startSec;
  final double durationSec;
  final double peakOpen;
  final double wide;
  final bool labialCloseEnd;
  final bool isPause;

  const _PhoneticBeat({
    required this.startSec,
    required this.durationSec,
    required this.peakOpen,
    required this.wide,
    this.labialCloseEnd = false,
    this.isPause = false,
  });
}

/// Generates realistic Vietnamese syllable viseme envelopes when raw WebAudio
/// FFT samples are unavailable (e.g., Web Speech fallback or mobile builds).
class _VietnamesePhoneticTimeline {
  static final RegExp _tokenRegex = RegExp(r'[a-zA-ZÀ-ỹ0-9]+|[,.;:!?–—]');
  static final RegExp _roundVowel = RegExp(
    r'[oôuưOÔUƯ]|oo|uô',
    caseSensitive: false,
  );
  static final RegExp _wideVowel = RegExp(
    r'[iíìỉĩịyýỳỷỹỵeéèẻẽẹêếềểễệ]',
    caseSensitive: false,
  );
  static final RegExp _openVowel = RegExp(
    r'[aáàảãạăắằẳẵặâấầẩẫậơớờởỡợ]',
    caseSensitive: false,
  );
  static final RegExp _labialEdge = RegExp(r'(^[mbpMBP]|[mpMP]$)');

  static List<_PhoneticBeat> build(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return const [];

    final beats = <_PhoneticBeat>[];
    double cursor = 0.0;

    for (final m in _tokenRegex.allMatches(clean)) {
      final tok = m.group(0)!;
      if (tok.length == 1 && ',.;:!?–—'.contains(tok)) {
        final pauseDur = (tok == ',' || tok == ';' || tok == ':') ? 0.16 : 0.28;
        beats.add(
          _PhoneticBeat(
            startSec: cursor,
            durationSec: pauseDur,
            peakOpen: 0.18,
            wide: 0.0,
            isPause: true,
          ),
        );
        cursor += pauseDur;
        continue;
      }

      // ~4.6 Vietnamese syllables/sec matching Blaze TTS speed=1.5
      final dur = (0.155 + (tok.length.clamp(1, 6) * 0.012));
      double open = 0.62;
      double wide = 0.1;

      if (_openVowel.hasMatch(tok)) {
        open = 0.86;
        wide = 0.25;
      } else if (_roundVowel.hasMatch(tok)) {
        open = 0.72;
        wide = -0.68;
      } else if (_wideVowel.hasMatch(tok)) {
        open = 0.56;
        wide = 0.72;
      }

      final hasLabial = _labialEdge.hasMatch(tok);
      beats.add(
        _PhoneticBeat(
          startSec: cursor,
          durationSec: dur,
          peakOpen: open,
          wide: wide,
          labialCloseEnd: hasLabial,
        ),
      );
      cursor += dur;
    }

    return beats;
  }

  static LipSyncFrame sample(List<_PhoneticBeat> beats, double elapsedSec) {
    if (beats.isEmpty) {
      final wave = 0.5 + 0.5 * math.sin(elapsedSec * 22.0);
      return LipSyncFrame(
        mouthOpen: 0.15 + wave * 0.65,
        mouthWide: 0.25 * math.sin(elapsedSec * 9.0),
        energy: wave * 0.8,
        active: true,
      );
    }

    final totalDur = beats.last.startSec + beats.last.durationSec;
    final t = totalDur > 0 ? (elapsedSec % totalDur) : 0.0;

    // Binary search active beat
    int lo = 0;
    int hi = beats.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (beats[mid].startSec <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }

    final beat = beats[lo];
    if (beat.isPause) {
      return const LipSyncFrame(
        mouthOpen: 0.20,
        mouthWide: 0.0,
        energy: 0.05,
        active: true,
      );
    }

    final phase = ((t - beat.startSec) / beat.durationSec).clamp(0.0, 1.0);
    // Crisp vowel swell in middle of syllable, consonant closure at edges
    final edgeFloor = beat.labialCloseEnd ? 0.02 : 0.14;
    final vowelCurve = math.sin(phase * math.pi);
    final open = edgeFloor + (beat.peakOpen - edgeFloor) * vowelCurve;

    return LipSyncFrame(
      mouthOpen: open.clamp(0.0, 1.0),
      mouthWide: beat.wide * vowelCurve,
      energy: (vowelCurve * 0.85).clamp(0.0, 1.0),
      active: true,
    );
  }
}
