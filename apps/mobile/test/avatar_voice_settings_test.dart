import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/assistant/presentation/providers/avatar_state_provider.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/avatar_voice_settings_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Avatar & Voice Settings Tests', () {
    test('Avatar3dNotifier selects and updates 3D model properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(avatar3dStateProvider);
      expect(initial.selectedModelPath, equals('assets/models/AvatarSample_A.glb'));
      expect(initial.modelName, equals('Linh (Anime 3D)'));

      // Switch to Linh Classic
      container
          .read(avatar3dStateProvider.notifier)
          .selectAvatarModel('assets/models/linh_avatar.glb', modelName: 'Linh Classic');

      final updated = container.read(avatar3dStateProvider);
      expect(updated.selectedModelPath, equals('assets/models/linh_avatar.glb'));
      expect(updated.modelName, equals('Linh Classic'));
      expect(updated.isLoading, isTrue);

      // Set loaded
      container.read(avatar3dStateProvider.notifier).setLoaded(
            modelName: 'Linh Classic',
            hasMorphTargets: true,
            hasSkeleton: true,
          );
      final loaded = container.read(avatar3dStateProvider);
      expect(loaded.isLoading, isFalse);
      expect(loaded.hasMorphTargets, isTrue);
    });

    test('VoiceAssistantNotifier updates speakerId and ttsSpeed properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(voiceAssistantProvider);
      expect(initial.speakerId, equals('DaNang-Nu-1-BL'));
      expect(initial.ttsSpeed, equals('1.5'));

      // Change to HaNoi-Nu-1-BL with 1.2x speed
      container.read(voiceAssistantProvider.notifier).setSpeakerId('HaNoi-Nu-1-BL');
      container.read(voiceAssistantProvider.notifier).setTtsSpeed('1.2');

      final updated = container.read(voiceAssistantProvider);
      expect(updated.speakerId, equals('HaNoi-Nu-1-BL'));
      expect(updated.ttsSpeed, equals('1.2'));
    });

    test('Pre-configured avatars and regional voices are populated correctly', () {
      expect(kAvailableAvatars.length, greaterThanOrEqualTo(2));
      final avatarPaths = kAvailableAvatars.map((a) => a.assetPath).toList();
      expect(avatarPaths, contains('assets/models/AvatarSample_A.glb'));
      expect(avatarPaths, contains('assets/models/linh_avatar.glb'));

      expect(kAvailableVoices.length, greaterThanOrEqualTo(5));
      final voiceIds = kAvailableVoices.map((v) => v.id).toList();
      expect(voiceIds, contains('DaNang-Nu-1-BL'));
      expect(voiceIds, contains('HaNoi-Nu-1-BL'));
      expect(voiceIds, contains('HaNoi-Nam-1-BL'));
      expect(voiceIds, contains('SaiGon-Nu-1-BL'));
      expect(voiceIds, contains('SaiGon-Nam-1-BL'));
      expect(voiceIds, contains('Hue-Nu-1-BL'));
    });
  });
}

