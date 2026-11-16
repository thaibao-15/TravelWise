import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/assistant/presentation/providers/avatar_state_provider.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/assistant/presentation/widgets/avatar_voice_settings_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Avatar & Voice Settings Tests', () {
    test('Avatar3dNotifier supports switching between 2D Photo and 3D Model modes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(avatar3dStateProvider);
      expect(initial.displayMode, equals(AvatarDisplayMode.photo2d));
      expect(initial.is2dMode, isTrue);
      expect(initial.is3dMode, isFalse);

      // Switch to 3D mode
      await container.read(avatar3dStateProvider.notifier).setDisplayMode(AvatarDisplayMode.model3d);
      final mode3dState = container.read(avatar3dStateProvider);
      expect(mode3dState.displayMode, equals(AvatarDisplayMode.model3d));
      expect(mode3dState.is2dMode, isFalse);
      expect(mode3dState.is3dMode, isTrue);

      // Switch back to 2D photo mode
      await container.read(avatar3dStateProvider.notifier).setDisplayMode(AvatarDisplayMode.photo2d);
      final mode2dState = container.read(avatar3dStateProvider);
      expect(mode2dState.displayMode, equals(AvatarDisplayMode.photo2d));
      expect(mode2dState.is2dMode, isTrue);
      expect(mode2dState.is3dMode, isFalse);
    });

    test('Avatar3dNotifier selects and updates 3D model properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(avatar3dStateProvider);
      expect(initial.selectedModelPath, equals('assets/models/Nam_C.glb'));
      expect(initial.modelName, equals('Nam (Anime 3D)'));

      // Switch to Linh (Anime 3D)
      container
          .read(avatar3dStateProvider.notifier)
          .selectAvatarModel('assets/models/AvatarSample_A.glb', modelName: 'Linh (Anime 3D)');

      final updated = container.read(avatar3dStateProvider);
      expect(updated.selectedModelPath, equals('assets/models/AvatarSample_A.glb'));
      expect(updated.modelName, equals('Linh (Anime 3D)'));
      expect(updated.isLoading, isTrue);

      // Set loaded
      container.read(avatar3dStateProvider.notifier).setLoaded(
            modelName: 'Linh (Anime 3D)',
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
      expect(avatarPaths, contains('assets/models/Nam_C.glb'));
      expect(avatarPaths, contains('assets/models/AvatarSample_A.glb'));

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

