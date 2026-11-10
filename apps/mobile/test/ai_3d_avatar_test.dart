import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/audio/lip_sync_frame.dart';
import 'package:mobile/features/assistant/presentation/models/glb_model.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/ai_3d_avatar.dart';
import 'package:mobile/features/assistant/services/avatar_animation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('3D Avatar & glTF Engine Tests', () {
    late Uint8List glbBytes;

    setUpAll(() {
      final file = File(r'd:\TravelWise 1\TravelWise\apps\mobile\assets\models\AvatarSample_A.glb');
      expect(file.existsSync(), isTrue, reason: 'AvatarSample_A.glb must exist in assets/models');
      glbBytes = file.readAsBytesSync();
    });

    test('GlbModel parses AvatarSample_A.glb binary structure correctly', () {
      final model = GlbModel.fromBytes(glbBytes, name: 'AvatarSample_A');
      expect(model.name, equals('AvatarSample_A'));
      expect(model.hasSkeleton, isTrue);
      expect(model.hasMorphTargets, isTrue);
      expect(model.hasTextures, isTrue);
      expect(model.skins, isNotEmpty);
      expect(model.materials.length, greaterThanOrEqualTo(10));
      expect(model.nodes.length, greaterThanOrEqualTo(6));
      expect(model.meshes.length, greaterThanOrEqualTo(5));

      // Must support standard vowel blend shapes + eye blink
      expect(model.morphTargetNames, contains('viseme_aa'));
      expect(model.morphTargetNames, contains('viseme_oh'));
      expect(model.morphTargetNames, contains('viseme_ee'));
      expect(model.morphTargetNames, contains('blink'));
      expect(model.morphTargetNames, contains('smile'));

      // Check node tree hierarchy
      final nodeNames = model.nodes.map((n) => n.name).toList();
      expect(nodeNames, contains('Head'));
      expect(nodeNames, contains('Chest'));
      expect(nodeNames, contains('LeftUpperArm'));
      expect(nodeNames, contains('RightUpperArm'));
    });

    test('AvatarAnimationService enforces zero mouth movement when silent', () {
      final service = AvatarAnimationService();

      // Case A: Idle state with silent audio
      final idleFrame = service.computeFrame(
        elapsedSeconds: 1.0,
        voiceState: VoiceState.idle,
        lipSync: LipSyncFrame.idle,
      );
      expect(idleFrame.visemeAa, equals(0.0));
      expect(idleFrame.visemeOh, equals(0.0));
      expect(idleFrame.visemeEe, equals(0.0));

      // Case B: Speaking state BUT audio frame is inactive / silent
      final inactiveSpeechFrame = service.computeFrame(
        elapsedSeconds: 2.0,
        voiceState: VoiceState.speaking,
        lipSync: const LipSyncFrame(mouthOpen: 0.0, mouthWide: 0.5, energy: 0.0, active: false),
      );
      expect(inactiveSpeechFrame.visemeAa, equals(0.0));
      expect(inactiveSpeechFrame.visemeOh, equals(0.0));
      expect(inactiveSpeechFrame.visemeEe, equals(0.0));

      // Case C: Listening state
      final listeningFrame = service.computeFrame(
        elapsedSeconds: 3.0,
        voiceState: VoiceState.listening,
        lipSync: LipSyncFrame.idle,
      );
      expect(listeningFrame.visemeAa, equals(0.0));
      // Attentive head pitch tilt forward towards user
      expect(listeningFrame.headPitch, lessThan(0.0));

      // Case D: Thinking state
      final thinkingFrame = service.computeFrame(
        elapsedSeconds: 4.0,
        voiceState: VoiceState.thinking,
        lipSync: LipSyncFrame.idle,
      );
      expect(thinkingFrame.visemeAa, equals(0.0));
      // Pensive gaze tilted upwards & sideways
      expect(thinkingFrame.headPitch, greaterThan(0.0));
    });

    test('AvatarAnimationService drives real-time morph targets when Blaze TTS plays', () {
      final service = AvatarAnimationService();

      // Feed multiple frames of open 'A' vowel audio
      AvatarFrameState lastFrame = const AvatarFrameState();
      for (int i = 0; i < 5; i++) {
        lastFrame = service.computeFrame(
          elapsedSeconds: 0.016 * i,
          voiceState: VoiceState.speaking,
          lipSync: const LipSyncFrame(
            mouthOpen: 0.85,
            mouthWide: 0.50,
            energy: 0.75,
            active: true,
          ),
        );
      }

      // Mouth must open with viseme_aa
      expect(lastFrame.visemeAa, greaterThan(0.50));
      final morphs = lastFrame.morphWeights;
      expect(morphs['viseme_aa'], greaterThan(0.50));

      // Now audio stops abruptly
      final stoppedFrame = service.computeFrame(
        elapsedSeconds: 1.0,
        voiceState: VoiceState.speaking,
        lipSync: LipSyncFrame.idle,
      );

      // Decays toward zero immediately
      expect(stoppedFrame.visemeAa, lessThan(lastFrame.visemeAa));
    });

    testWidgets('Ai3dAvatar renders gracefully and handles orbit rotation updates', (tester) async {
      final lipSyncNotifier = ValueNotifier<LipSyncFrame>(LipSyncFrame.idle);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 380,
                height: 520,
                child: Ai3dAvatar(
                  voiceState: VoiceState.listening,
                  lipSyncListenable: lipSyncNotifier,
                ),
              ),
            ),
          ),
        ),
      );

      // Pump single frames rather than pumpAndSettle because of repeating animation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(Ai3dAvatar), findsOneWidget);

      // Status pill should display listening state
      expect(find.text('Nam (Anime 3D) • Đang nghe bạn'), findsOneWidget);

      // Test drag gesture for camera orbit
      await tester.drag(find.byType(Ai3dAvatar), const Offset(50, -20));
      await tester.pump(const Duration(milliseconds: 50));

      lipSyncNotifier.dispose();
    });
  });
}
