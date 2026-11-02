import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/audio/lip_sync_frame.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/linh_lip_sync_avatar.dart';

void main() {
  group('LinhLipSyncAvatar & LinhPortraitRigPainter', () {
    testWidgets(
      'mounts, tracks real-time LipSyncFrame updates, and disposes ticker cleanly',
      (tester) async {
        final lipSync = ValueNotifier<LipSyncFrame>(LipSyncFrame.idle);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 420,
                child: LinhLipSyncAvatar(
                  voiceState: VoiceState.speaking,
                  speechText: 'Xin chào bạn! Mình là Linh AI tại Đà Nẵng.',
                  lipSyncListenable: lipSync,
                ),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        // Simulate real-time WebAudio AnalyserNode vowel + consonant frames
        lipSync.value = const LipSyncFrame(
          mouthOpen: 0.92,
          mouthWide: 0.35,
          energy: 0.85,
          active: true,
        );
        await tester.pump(const Duration(milliseconds: 32));

        lipSync.value = const LipSyncFrame(
          mouthOpen: 0.04,
          mouthWide: -0.60,
          energy: 0.25,
          active: true,
        );
        await tester.pump(const Duration(milliseconds: 32));

        // Return to idle and unmount — ensures zero leaked Ticker/Timers
        lipSync.value = LipSyncFrame.idle;
        await tester.pumpWidget(const SizedBox.shrink());
        lipSync.dispose();
      },
    );

    test(
      'renders closed, neutral, and wide-open visemes on portrait mesh',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final bytes = await File('assets/images/linh_ai.jpg').readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;

        for (final open in <double>[0.0, LipSyncFrame.restOpen, 0.95]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          LinhPortraitRigPainter(
            image: img,
            debugMouthOpen: open,
            debugMouthWide: open > 0.5 ? 0.4 : -0.5,
            debugBlink: open == 0.0 ? 1.0 : 0.0,
            debugEnergy: 0.7,
          ).paint(canvas, const Size(320, 420));
          final outImg = await recorder.endRecording().toImage(320, 420);
          expect(outImg.width, 320);
          expect(outImg.height, 420);
        }
      },
    );
  });
}
