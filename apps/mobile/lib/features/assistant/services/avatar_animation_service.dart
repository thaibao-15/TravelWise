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
  final double chestPitch;
  final double chestRoll;

  /// Left and right arm gesture 3D rotations (pitch, roll, yaw) in radians
  final double leftArmPitch;
  final double leftArmRoll;
  final double leftArmYaw;
  final double leftForeArmPitch;
  final double leftForeArmYaw;
  final double rightArmPitch;
  final double rightArmRoll;
  final double rightArmYaw;
  final double rightForeArmPitch;
  final double rightForeArmYaw;

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
    this.chestPitch = 0.0,
    this.chestRoll = 0.0,
    this.leftArmPitch = 0.0,
    this.leftArmRoll = 0.0,
    this.leftArmYaw = 0.0,
    this.leftForeArmPitch = 0.0,
    this.leftForeArmYaw = 0.0,
    this.rightArmPitch = 0.0,
    this.rightArmRoll = 0.0,
    this.rightArmYaw = 0.0,
    this.rightForeArmPitch = 0.0,
    this.rightForeArmYaw = 0.0,
  });

  Map<String, double> get morphWeights => {
        'viseme_aa': visemeAa,
        'viseme_oh': visemeOh,
        'viseme_ee': visemeEe,
        'viseme_ih': (visemeEe * 0.45).clamp(0.0, 1.0),
        'viseme_ou': (visemeOh * 0.45).clamp(0.0, 1.0),
        'blink': blinkWeight,
        'smile': smileWeight,
        // VRM 1.0 & ARKit standard aliases
        'A': visemeAa,
        'O': visemeOh,
        'E': visemeEe,
        'I': (visemeEe * 0.45).clamp(0.0, 1.0),
        'U': (visemeOh * 0.45).clamp(0.0, 1.0),
        'Blink': blinkWeight,
        'Joy': smileWeight,
        'mouthOpen': visemeAa,
        'Fcl_MTH_A': visemeAa,
        'Fcl_MTH_O': visemeOh,
        'Fcl_MTH_E': visemeEe,
        'Fcl_MTH_I': (visemeEe * 0.45).clamp(0.0, 1.0),
        'Fcl_MTH_U': (visemeOh * 0.45).clamp(0.0, 1.0),
        'Fcl_EYE_Close': blinkWeight,
        'Fcl_MTH_Fun': smileWeight,
      };
}

/// Service that translates Voice AI state and real-time audio LipSyncFrame into
/// natural 60fps skeletal gestures and blend-shape morph weights.
class AvatarAnimationService {
  double _blinkTimer = 0.0;
  double _nextBlinkTime = 3.5;
  double _currentBlink = 0.0;
  bool _isDoubleBlink = false;

  // Smoothed phoneme targets for natural lip-sync
  double _smoothAa = 0.0;
  double _smoothOh = 0.0;
  double _smoothEe = 0.0;

  void reset() {
    _blinkTimer = 0.0;
    _nextBlinkTime = 3.5;
    _currentBlink = 0.0;
    _isDoubleBlink = false;
    _smoothAa = 0.0;
    _smoothOh = 0.0;
    _smoothEe = 0.0;
  }

  /// Computes frame animation targets.
  /// [elapsedSeconds] is the continuous wall-clock elapsed seconds.
  /// [voiceState] indicates AI operational state.
  /// [lipSync] is the real-time Blaze TTS audio lip-sync frame from Web Audio / AnalyserNode.
  /// [speechText] is the Vietnamese text currently being spoken.
  AvatarFrameState computeFrame({
    required double elapsedSeconds,
    required VoiceState voiceState,
    required LipSyncFrame lipSync,
    String speechText = '',
  }) {
    // 1. Natural autonomous blinking with occasional double-blinks (every 2.8..4.5s)
    _blinkTimer += 0.0166;
    if (_blinkTimer >= _nextBlinkTime) {
      final double blinkDuration = _isDoubleBlink ? 0.36 : 0.18;
      final blinkProgress = (_blinkTimer - _nextBlinkTime) / blinkDuration;
      if (blinkProgress >= 1.0) {
        _blinkTimer = 0.0;
        _currentBlink = 0.0;
        _isDoubleBlink = math.Random().nextDouble() < 0.28;
        _nextBlinkTime = 2.5 + math.Random().nextDouble() * 2.8;
      } else {
        if (_isDoubleBlink) {
          _currentBlink = math.sin(blinkProgress * 2 * math.pi).abs();
        } else {
          _currentBlink = math.sin(blinkProgress * math.pi);
        }
      }
    }

    // 2. Rich state-specific skeletal posing, expressive actions, and looking gestures
    double headPitch = 0.0;
    double headYaw = 0.0;
    double headRoll = 0.0;
    double smile = 0.28;
    double chestBreath = math.sin(elapsedSeconds * 1.9) * 0.0035;
    double chestPitch = 0.0;
    double chestRoll = 0.0;

    double leftArmPitch = 0.0;
    double leftArmRoll = 0.0;
    double leftArmYaw = 0.0;
    double leftForeArmPitch = 0.0;
    double leftForeArmYaw = 0.0;
    double rightArmPitch = 0.0;
    double rightArmRoll = 0.0;
    double rightArmYaw = 0.0;
    double rightForeArmPitch = 0.0;
    double rightForeArmYaw = 0.0;

    switch (voiceState) {
      case VoiceState.idle:
        // Micro-sway tự nhiên, nhịp thở thư thái và tư thế sẵn sàng đón chào
        headYaw = math.sin(elapsedSeconds * 0.6) * 0.038;
        headPitch = math.sin(elapsedSeconds * 0.8) * 0.022;
        headRoll = math.cos(elapsedSeconds * 0.5) * 0.020;
        chestRoll = math.sin(elapsedSeconds * 0.5) * 0.012;
        smile = 0.28;
        // Tay thả lỏng hai bên với chuyển động thở tự nhiên
        leftArmPitch = 0.04 + math.sin(elapsedSeconds * 1.9) * 0.015;
        rightArmPitch = 0.04 + math.cos(elapsedSeconds * 1.9) * 0.015;
        break;

      case VoiceState.listening:
        // Tư thế chú tâm: Thân hơi nghiêng nhẹ về phía trước, đầu nghiêng tò mò
        chestPitch = -0.035;
        headPitch = -0.065 + math.sin(elapsedSeconds * 2.8) * 0.025; // Gật đầu thấu hiểu nhẹ nhàng
        headYaw = -0.04 + math.sin(elapsedSeconds * 1.2) * 0.018;
        headRoll = 0.065; // Nghiêng đầu chăm chú lắng nghe
        smile = 0.36; // Nụ cười khích lệ
        // Cử chỉ tay phải nâng nhẹ tiếp nhận thông tin từ người dùng
        rightArmPitch = 0.26 + math.sin(elapsedSeconds * 2.0) * 0.02;
        rightArmRoll = -0.14;
        rightArmYaw = 0.12;
        leftArmPitch = 0.05;
        break;

      case VoiceState.thinking:
      case VoiceState.processing:
      case VoiceState.connecting:
        // Tư thế đăm chiêu suy nghĩ kinh điển: Ánh mắt hơi hướng lên góc trái, tay nâng về phía cằm
        headPitch = 0.095 + math.sin(elapsedSeconds * 1.8) * 0.015;
        headYaw = -0.14 + math.sin(elapsedSeconds * 1.4) * 0.020;
        headRoll = -0.06;
        smile = 0.12; // Miệng chúm lại tập trung suy nghĩ
        // Cử chỉ tay phải đặt gần cằm / ngực trong tư thế suy ngẫm
        rightArmPitch = 0.52 + math.sin(elapsedSeconds * 2.0) * 0.025;
        rightArmRoll = -0.24;
        rightArmYaw = 0.30;
        // Tay trái hơi nâng đỡ nhẹ
        leftArmPitch = 0.10;
        leftArmRoll = 0.08;
        break;

      case VoiceState.speaking:
        // Tư thế thuyết minh / hướng dẫn viên du lịch sinh động và tràn đầy năng lượng!
        // Gật đầu nhịp nhàng theo câu nói nhấn mạnh từng ý
        headPitch = math.sin(elapsedSeconds * 4.4) * 0.046 +
            math.sin(elapsedSeconds * 2.2) * 0.026;
        headYaw = math.sin(elapsedSeconds * 2.2) * 0.062;
        headRoll = math.cos(elapsedSeconds * 1.8) * 0.034;
        chestPitch = math.sin(elapsedSeconds * 2.2) * 0.018;
        chestRoll = math.cos(elapsedSeconds * 1.8) * 0.015;
        smile = 0.38 + math.sin(elapsedSeconds * 3.2) * 0.12; // Cười rạng rỡ khi trò chuyện

        // Cử chỉ tay sinh động luân phiên: Mở tay hướng dẫn người dùng
        rightArmPitch = 0.28 + math.sin(elapsedSeconds * 2.8) * 0.18;
        rightArmRoll = -0.15 + math.cos(elapsedSeconds * 2.8) * 0.08;
        rightArmYaw = 0.18 + math.sin(elapsedSeconds * 2.8) * 0.10;

        leftArmPitch = 0.14 + math.cos(elapsedSeconds * 2.4) * 0.12;
        leftArmRoll = 0.10 + math.sin(elapsedSeconds * 2.4) * 0.06;
        leftArmYaw = -0.12;
        break;

      case VoiceState.error:
        // Tư thế điềm tĩnh, an ủi người dùng thử lại
        headPitch = 0.04;
        headYaw = 0.0;
        headRoll = 0.02;
        smile = 0.10;
        break;
    }

    // 3. Khớp chuyển động môi (Strict & Natural Phonetic Lip-Sync)
    double targetAa = 0.0;
    double targetOh = 0.0;
    double targetEe = 0.0;

    if (voiceState == VoiceState.speaking) {
      if (lipSync.active && lipSync.energy > 0.015) {
        // A. Đồng bộ trực tiếp theo tín hiệu âm thanh Blaze TTS thực tế (Web Audio Analyser)
        final open = lipSync.mouthOpen.clamp(0.0, 1.0);
        final wide = lipSync.mouthWide.clamp(-1.0, 1.0); // Giữ nguyên dấu âm/dương chuẩn phonetic!

        if (wide < -0.18 || (wide >= 0.0 && wide < 0.38)) {
          // Âm tròn môi (O, Ô, U, Ơ) -> Kích hoạt viseme_oh
          targetOh = (open * 0.95).clamp(0.0, 1.0);
          targetAa = (open * 0.20).clamp(0.0, 1.0);
          targetEe = 0.0;
        } else if (wide > 0.62) {
          // Âm bẹt mở rộng (E, Ê, I, Y) -> Kích hoạt viseme_ee
          targetEe = (open * 0.92).clamp(0.0, 1.0);
          targetAa = (open * 0.25).clamp(0.0, 1.0);
          targetOh = 0.0;
        } else {
          // Âm mở hàm trung tâm (A, Ă, Â): Hỗ trợ cả mouthWide ~0.0 và ~0.50
          targetAa = (open * 1.0).clamp(0.0, 1.0);
          targetEe = (open * 0.15).clamp(0.0, 1.0);
          targetOh = 0.0;
        }
      } else if (lipSync.active && lipSync.energy <= 0.015) {
        // Lúc ngừng hơi / ngắt câu giữa các từ: Miệng khép lại dứt khoát
        targetAa = 0.0;
        targetOh = 0.0;
        targetEe = 0.0;
      } else if (speechText.trim().isNotEmpty) {
        // B. Fallback thông minh: Tạo nhịp điệu phát âm chuẩn âm tiết Tiếng Việt theo nội dung đang đọc
        final viseme = _sampleVietnameseViseme(speechText, elapsedSeconds);
        targetAa = viseme.aa;
        targetOh = viseme.oh;
        targetEe = viseme.ee;
      }
    }

    // Smooth lerp (Attack nhanh 0.44 để khớp tức thì với âm thanh, Decay 0.32)
    _smoothAa += (targetAa - _smoothAa) * 0.44;
    _smoothOh += (targetOh - _smoothOh) * 0.44;
    _smoothEe += (targetEe - _smoothEe) * 0.44;

    // Ngưỡng cắt nhẹ để tránh rung giật môi khi im lặng
    if (_smoothAa < 0.012) _smoothAa = 0.0;
    if (_smoothOh < 0.012) _smoothOh = 0.0;
    if (_smoothEe < 0.012) _smoothEe = 0.0;

    return AvatarFrameState(
      headPitch: headPitch,
      headYaw: headYaw,
      headRoll: headRoll,
      blinkWeight: (_currentBlink + (voiceState == VoiceState.thinking ? 0.16 : 0.0)).clamp(0.0, 1.0),
      visemeAa: _smoothAa.clamp(0.0, 1.0),
      visemeOh: _smoothOh.clamp(0.0, 1.0),
      visemeEe: _smoothEe.clamp(0.0, 1.0),
      smileWeight: smile.clamp(0.0, 1.0),
      chestBreath: chestBreath,
      chestPitch: chestPitch,
      chestRoll: chestRoll,
      leftArmPitch: leftArmPitch,
      leftArmRoll: leftArmRoll,
      leftArmYaw: leftArmYaw,
      leftForeArmPitch: leftForeArmPitch,
      leftForeArmYaw: leftForeArmYaw,
      rightArmPitch: rightArmPitch,
      rightArmRoll: rightArmRoll,
      rightArmYaw: rightArmYaw,
      rightForeArmPitch: rightForeArmPitch,
      rightForeArmYaw: rightForeArmYaw,
    );
  }

  /// Bộ phân tích phát âm âm tiết Tiếng Việt theo thời gian thực
  _VisemeSample _sampleVietnameseViseme(String text, double elapsedSec) {
    final clean = text.trim();
    if (clean.isEmpty) return const _VisemeSample(aa: 0.0, oh: 0.0, ee: 0.0);

    final words = clean.split(RegExp(r'\s+'));
    if (words.isEmpty) return const _VisemeSample(aa: 0.0, oh: 0.0, ee: 0.0);

    const syllableDur = 0.22;
    final totalDur = words.length * syllableDur;
    final timeInCycle = elapsedSec % (totalDur + 0.5);

    if (timeInCycle >= totalDur) {
      return const _VisemeSample(aa: 0.0, oh: 0.0, ee: 0.0);
    }

    final wordIdx = (timeInCycle / syllableDur).floor().clamp(0, words.length - 1);
    final word = words[wordIdx].toLowerCase();
    final wordProgress = (timeInCycle % syllableDur) / syllableDur;

    double openness = math.sin(wordProgress * math.pi).clamp(0.0, 1.0);

    // Âm môi kết thúc (m, p, b): Khép môi sớm
    if (word.endsWith('m') || word.endsWith('p') || word.endsWith('b')) {
      if (wordProgress > 0.60) openness = 0.0;
    }

    if (RegExp(r'[oôuươớờởỡợúùủũụóòỏõọ]').hasMatch(word)) {
      return _VisemeSample(aa: openness * 0.20, oh: openness * 0.90, ee: 0.0);
    } else if (RegExp(r'[ieêyíìỉĩịéèẻẽẹếềểễệ]').hasMatch(word)) {
      return _VisemeSample(aa: openness * 0.20, oh: 0.0, ee: openness * 0.90);
    } else {
      return _VisemeSample(aa: openness * 0.95, oh: 0.0, ee: openness * 0.15);
    }
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
        final gesture = Quaternion.axisAngle(Vector3(1, 0, 0), frame.leftArmPitch);
        node.rotation.setFrom(baseQ * gesture);
      } else if (node.name == 'RightUpperArm') {
        final baseQ = Quaternion(0.0, 0.0, 0.10, 0.995);
        final gesture = Quaternion.axisAngle(Vector3(1, 0, 0), frame.rightArmPitch);
        node.rotation.setFrom(baseQ * gesture);
      }
    }
  }
}

class _VisemeSample {
  final double aa;
  final double oh;
  final double ee;

  const _VisemeSample({
    required this.aa,
    required this.oh,
    required this.ee,
  });
}
