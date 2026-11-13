import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/assistant/presentation/models/glb_model.dart';

void main() {
  test('GlbModel parses Nam_C.glb properly', () {
    final file = File(r'd:\TravelWise 1\TravelWise\apps\mobile\assets\models\Nam_C.glb');
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();
    final model = GlbModel.fromBytes(bytes, name: 'Nam_C');

    expect(model.name, equals('Nam_C'));
    expect(model.hasSkeleton, isTrue);
    expect(model.hasMorphTargets, isTrue);
    expect(model.hasTextures, isTrue);
    expect(model.skins, isNotEmpty);
    expect(model.materials.length, greaterThanOrEqualTo(10));
    expect(model.nodes.length, greaterThanOrEqualTo(6));
    expect(model.meshes.length, greaterThanOrEqualTo(5));

    expect(model.morphTargetNames, contains('viseme_aa'));
    expect(model.morphTargetNames, contains('viseme_oh'));
    expect(model.morphTargetNames, contains('viseme_ee'));
    expect(model.morphTargetNames, contains('blink'));
    expect(model.morphTargetNames, contains('smile'));

    final nodeNames = model.nodes.map((n) => n.name).toList();
    expect(nodeNames, contains('Head'));
    expect(nodeNames, contains('Chest'));
    expect(nodeNames, contains('LeftUpperArm'));
    expect(nodeNames, contains('RightUpperArm'));
  });
}

