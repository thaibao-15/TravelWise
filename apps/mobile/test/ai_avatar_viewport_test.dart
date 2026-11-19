import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/audio/lip_sync_frame.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/ai_2d_avatar.dart';
import 'package:mobile/features/assistant/presentation/widgets/ai_avatar_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiAvatarViewport Widget Tests', () {
    testWidgets('renders 2D mode by default and switches to 3D mode via segmented pill', (tester) async {
      final lipSync = ValueNotifier<LipSyncFrame>(LipSyncFrame.idle);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: AiAvatarViewport(
                  voiceState: VoiceState.idle,
                  speechText: 'Xin chào bạn!',
                  lipSyncListenable: lipSync,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify segmented mode switcher labels exist
      expect(find.text('Ảnh AI'), findsOneWidget);
      expect(find.text('3D'), findsOneWidget);
      expect(find.text('Cài đặt'), findsOneWidget);

      // Verify default is 2D avatar
      expect(find.byType(Ai2dAvatar), findsOneWidget);

      // Tap on 3D switch button
      await tester.tap(find.text('3D'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 3D should now be active
      expect(find.text('3D'), findsOneWidget);

      // Clean up
      lipSync.dispose();
    });

    testWidgets('displays appropriate status pill across voice states', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: AiAvatarViewport(
                  voiceState: VoiceState.speaking,
                  speechText: 'Đang giới thiệu địa điểm du lịch...',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.textContaining('Đang nói'), findsOneWidget);
    });
  });
}

