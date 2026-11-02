import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import '../../../core/audio/lip_sync_frame.dart';
import '../presentation/models/glb_model.dart';
import '../presentation/providers/voice_assistant_provider.dart';

/// Poses and morph weights computed per-frame for 3D avatar rendering.
class AvatarFrameState {
  /// Head tilt angles (pitch, yaw, roll) in radians
  final double headPitch;
  final double headYaw;
  final double headRoll;

  /// Eye blink weight [0.0..1.0]
  final double blinkWeight;

  /// Phonetic vowel morph weights [0.0..1.0]
  final double visemeAa;
  final double visemeOh;
  final double visemeEe;

  /// Welcoming smile weight [0.0..1.0]
  final double smileWeight;

  /// Subtle breathing chest displacement
  final double chestBreath;

  /// Left and right arm gesture rotation adjustments (radians)
  final double leftArmPitch;
  final double leftArmRoll;
  final double rightArmPitch;
  final double rightArmRoll;

  const AvatarFrameState({
    this.headPitch = 0.0,
    this.headYaw = 0.0,
    this.headRoll = 0.0,
    this.blinkWeight = 0.0,
    this.visemeAa = 0.0,
    this.visemeOh = 0.0,
    this.visemeEe = 0.0,
    this.smileWeight = 0.25,
    this.chestBreath = 0.0,
    this.leftArmPitch = 0.0,
    this.leftArmRoll = 0.0,
    this.rightArmPitch = 0.0,
    this.rightArmRoll = 0.0,
  });

  Map<String, double> get morphWeights => {
    'viseme_aa': visemeAa,
    'viseme_oh': visemeOh,
    'viseme_ee': visemeEe,
    'blink': blinkWeight,
    'smile': smileWeight,
    // VRM & ARKit standard aliases
    'A': visemeAa,
    'O': visemeOh,
    'E': visemeEe,
    'Blink': blinkWeight,
    'Joy': smileWeight,
    'mouthOpen': visemeAa,
  };
}

/// Service that translates Voice AI state and real-time audio LipSyncFrame into
/// natural 60fps skeletal gestures and blend-shape morph weights.
class AvatarAnimationService {
  double _blinkTimer = 0.0;
  double _nextBlinkTime = 3.5;
  double _currentBlink = 0.0;

  // Smoothed phoneme targets for natural lip-sync
  double _smoothAa = 0.0;
  double _smoothOh = 0.0;
  double _smoothEe = 0.0;
  VoiceState? _lastVoiceState;
  double? _speakingStartSeconds;
  double? _speakingEndSeconds;
  String _lastSpeechText = '';

  void reset() {
    _blinkTimer = 0.0;
    _nextBlinkTime = 3.5;
    _currentBlink = 0.0;
    _smoothAa = 0.0;
    _smoothOh = 0.0;
    _smoothEe = 0.0;
    _lastVoiceState = null;
    _speakingStartSeconds = null;
    _speakingEndSeconds = null;
    _lastSpeechText = '';
  }

  /// Computes frame animation targets.
  /// [elapsedSeconds] is the continuous wall-clock elapsed seconds.
  /// [voiceState] indicates AI operational state.
  /// [lipSync] is the real-time Blaze TTS audio lip-sync frame from Web Audio / AnalyserNode.
  AvatarFrameState computeFrame({
    required double elapsedSeconds,
    required VoiceState voiceState,
    required LipSyncFrame lipSync,
    required String speechText,
  }) {
    if (_lastVoiceState != voiceState) {
      if (_lastVoiceState == VoiceState.speaking &&
          voiceState != VoiceState.speaking) {
        _speakingEndSeconds = elapsedSeconds;
      }
      _lastVoiceState = voiceState;
      if (voiceState == VoiceState.speaking) {
        _speakingStartSeconds = elapsedSeconds;
        _speakingEndSeconds = null;
      }
    }
    if (speechText.trim().isNotEmpty) _lastSpeechText = speechText;

    // 1. Natural autonomous blinking (every 3..6s, 180ms duration)
    _blinkTimer += 0.0166;
    if (_blinkTimer >= _nextBlinkTime) {
      final blinkProgress = (_blinkTimer - _nextBlinkTime) / 0.18;
      if (blinkProgress >= 1.0) {
        _blinkTimer = 0.0;
        _currentBlink = 0.0;
        _nextBlinkTime = 2.8 + math.Random().nextDouble() * 3.2;
      } else {
        _currentBlink = math.sin(blinkProgress * math.pi);
      }
    }

    // 2. State-specific skeletal posing and look-at gestures
    double headPitch = 0.0;
    double headYaw = 0.0;
    double headRoll = 0.0;
    double smile = 0.22;
    double leftArmPitch = 0.0;
    double leftArmRoll = 0.0;
    double rightArmPitch = 0.0;
    double rightArmRoll = 0.0;

    final chestBreath = math.sin(elapsedSeconds * 2.2) * 0.003;

    switch (voiceState) {
      case VoiceState.idle:
        // Gentle micro-sway and warm resting posture
        headYaw = math.sin(elapsedSeconds * 0.6) * 0.035;
        headPitch = math.sin(elapsedSeconds * 0.8) * 0.020;
        headRoll = math.cos(elapsedSeconds * 0.5) * 0.015;
        smile = 0.25;
        break;

      case VoiceState.listening:
        // Attentive posture: leaned slightly forward, head tilted toward user
        headPitch = -0.065 + math.sin(elapsedSeconds * 1.5) * 0.012;
        headYaw = math.sin(elapsedSeconds * 1.0) * 0.025;
        headRoll = 0.045; // Inquisitive head tilt
        smile = 0.32;
        // Right hand lifted slightly in attentive gesture
        rightArmPitch = 0.12;
        rightArmRoll = -0.05;
        break;

      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        // Pensive posture: gaze angled slightly upward-left
        headPitch = 0.085 + math.sin(elapsedSeconds * 2.5) * 0.015;
        headYaw = -0.12 + math.sin(elapsedSeconds * 1.8) * 0.025;
        headRoll = -0.05;
        smile = 0.15;
        // Pensive arm posture
        rightArmPitch = 0.22;
        rightArmRoll = -0.10;
        break;

      case VoiceState.speaking:
        // Expressive conversational nodding and hand gestures
        headPitch =
            math.sin(elapsedSeconds * 4.2) * 0.045 +
            math.sin(elapsedSeconds * 1.8) * 0.025;
        headYaw = math.sin(elapsedSeconds * 2.4) * 0.055;
        headRoll = math.cos(elapsedSeconds * 2.0) * 0.028;
        smile = 0.28 + math.sin(elapsedSeconds * 3.0) * 0.08;
        // Natural alternating conversational hand emphasis
        leftArmPitch = math.sin(elapsedSeconds * 2.8) * 0.10;
        rightArmPitch = math.cos(elapsedSeconds * 2.8) * 0.12;
        break;

      case VoiceState.error:
        // Calm reset posture
        headPitch = 0.03;
        headYaw = 0.0;
        headRoll = 0.0;
        smile = 0.10;
        break;
    }

    // 3. Strict Real-Time Blaze TTS Audio Lip-Sync
    // Requirement: "Không giả lập nhép môi liên tục khi AI chưa phát âm thanh."
    // If AI is not in `speaking` state, or audio is silent / ended (lipSync.active == false),
    // mouth MUST snap strictly to 0.0!
    double targetAa = 0.0;
    double targetOh = 0.0;
    double targetEe = 0.0;

    final isInSpeakingGracePeriod =
        _speakingEndSeconds != null &&
        elapsedSeconds - _speakingEndSeconds! < 1.0;
    final shouldAnimateMouth =
        voiceState == VoiceState.speaking || isInSpeakingGracePeriod;

    if (shouldAnimateMouth) {
      final hasAudioLipSync = lipSync.active && lipSync.energy > 0.02;
      final speakingElapsed =
          elapsedSeconds - (_speakingStartSeconds ?? elapsedSeconds);
      final fallbackText = speechText.trim().isNotEmpty
          ? speechText
          : _lastSpeechText;
      final fallback = speakingElapsed < 2.5
          ? (0.0, 0.0)
          : _fallbackViseme(fallbackText, speakingElapsed - 1.5);
      final open = hasAudioLipSync
          ? lipSync.mouthOpen.clamp(0.0, 1.0)
          : fallback.$1;
      final wide = hasAudioLipSync
          ? lipSync.mouthWide.clamp(-1.0, 1.0)
          : fallback.$2;

      if (wide > 0.58) {
        // High F2 formant -> wide spread vowel ("E", "I", "Ê")
        targetEe = (open * 0.85).clamp(0.0, 1.0);
        targetAa = (open * 0.35).clamp(0.0, 1.0);
      } else if (wide < 0.42) {
        // Low F2 formant -> rounded vowel ("O", "U", "Ô")
        targetOh = (open * 0.90).clamp(0.0, 1.0);
        targetAa = (open * 0.30).clamp(0.0, 1.0);
      } else {
        // Open central vowel ("A", "Ă", "Â")
        targetAa = open;
        targetOh = open * 0.20;
      }
    }

    // Smooth lerp (fast attack ~0.35, gentle decay ~0.25)
    _smoothAa += (targetAa - _smoothAa) * 0.38;
    _smoothOh += (targetOh - _smoothOh) * 0.38;
    _smoothEe += (targetEe - _smoothEe) * 0.38;

    // Zero cut-off to prevent micro-twitching when silent
    if (_smoothAa < 0.015) _smoothAa = 0.0;
    if (_smoothOh < 0.015) _smoothOh = 0.0;
    if (_smoothEe < 0.015) _smoothEe = 0.0;

    return AvatarFrameState(
      headPitch: headPitch,
      headYaw: headYaw,
      headRoll: headRoll,
      blinkWeight: _currentBlink.clamp(0.0, 1.0),
      visemeAa: _smoothAa.clamp(0.0, 1.0),
      visemeOh: _smoothOh.clamp(0.0, 1.0),
      visemeEe: _smoothEe.clamp(0.0, 1.0),
      smileWeight: smile.clamp(0.0, 1.0),
      chestBreath: chestBreath,
      leftArmPitch: leftArmPitch,
      leftArmRoll: leftArmRoll,
      rightArmPitch: rightArmPitch,
      rightArmRoll: rightArmRoll,
    );
  }

  (double, double) _fallbackViseme(String text, double elapsedSeconds) {
    final characters = text.trim().toLowerCase().runes.toList();
    if (characters.isEmpty) {
      final pulse = 0.5 + 0.5 * math.sin(elapsedSeconds * 18.0);
      return (0.28 + pulse * 0.42, 0.0);
    }

    final index = (elapsedSeconds * 9.0).floor() % characters.length;
    final character = String.fromCharCode(characters[index]);

    if (',.;:!?'.contains(character)) return (0.08, 0.0);
    if (character.trim().isEmpty) return (0.10, 0.0);
    if ('oôơuư'.contains(character)) return (0.68, -0.75);
    if ('eêiịy'.contains(character)) return (0.56, 0.75);
    if ('aăâ'.contains(character)) return (0.86, 0.12);
    return (0.42, 0.0);
  }

  /// Applies skeletal bone rotations directly onto [model]'s nodes.
  void applyPosingToNodes(GlbModel model, AvatarFrameState frame) {
    for (final node in model.nodes) {
      if (node.name == 'Head') {
        final qPitch = Quaternion.axisAngle(Vector3(1, 0, 0), frame.headPitch);
        final qYaw = Quaternion.axisAngle(Vector3(0, 1, 0), frame.headYaw);
        final qRoll = Quaternion.axisAngle(Vector3(0, 0, 1), frame.headRoll);
        node.rotation.setFrom(qYaw * qPitch * qRoll);
      } else if (node.name == 'Chest') {
        node.translation.y = frame.chestBreath;
      } else if (node.name == 'LeftUpperArm') {
        final baseQ = Quaternion(0.0, 0.0, -0.10, 0.995);
        final gesture = Quaternion.axisAngle(
          Vector3(1, 0, 0),
          frame.leftArmPitch,
        );
        node.rotation.setFrom(baseQ * gesture);
      } else if (node.name == 'RightUpperArm') {
        final baseQ = Quaternion(0.0, 0.0, 0.10, 0.995);
        final gesture = Quaternion.axisAngle(
          Vector3(1, 0, 0),
          frame.rightArmPitch,
        );
        node.rotation.setFrom(baseQ * gesture);
      }
    }
  }
}
