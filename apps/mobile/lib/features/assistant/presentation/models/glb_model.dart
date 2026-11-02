import 'dart:convert';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart';

/// Represents a single 3D primitive containing vertex positions, normals,
/// optional vertex colors, index buffer, and optional morph targets.
class GlbPrimitive {
  final Float32List positions;
  final Float32List normals;
  final Float32List? colors;
  final Uint16List indices;
  final List<Float32List> morphPositionDeltas;
  final List<String> morphTargetNames;

  const GlbPrimitive({
    required this.positions,
    required this.normals,
    this.colors,
    required this.indices,
    this.morphPositionDeltas = const [],
    this.morphTargetNames = const [],
  });

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// Represents a 3D Mesh consisting of one or more primitives.
class GlbMesh {
  final String name;
  final List<GlbPrimitive> primitives;

  const GlbMesh({
    required this.name,
    required this.primitives,
  });
}

/// Represents a node in the 3D scene hierarchy (Skeleton / Bone / Mesh Transform).
class GlbNode {
  final String name;
  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;
  final int? meshIndex;
  final List<int> children;

  GlbNode({
    required this.name,
    required this.translation,
    required this.rotation,
    required this.scale,
    this.meshIndex,
    this.children = const [],
  });

  Matrix4 get localTransform {
    return Matrix4.compose(translation, rotation, scale);
  }
}

/// Fully parsed glTF 2.0 Binary (.glb) / VRM humanoid avatar model.
class GlbModel {
  final String name;
  final List<GlbMesh> meshes;
  final List<GlbNode> nodes;
  final List<int> rootNodes;
  final List<String> morphTargetNames;

  const GlbModel({
    required this.name,
    required this.meshes,
    required this.nodes,
    required this.rootNodes,
    this.morphTargetNames = const [],
  });

  bool get hasMorphTargets => morphTargetNames.isNotEmpty;
  bool get hasSkeleton => nodes.length > 1;

  /// Fast binary glTF 2.0 parser reading directly from in-memory byte buffer.
  factory GlbModel.fromBytes(Uint8List bytes, {String name = 'Avatar'}) {
    final byteData = ByteData.sublistView(bytes);
    if (bytes.length < 20) {
      throw FormatException('Tệp GLB quá nhỏ hoặc không hợp lệ.');
    }

    final magic = byteData.getUint32(0, Endian.little);
    // 0x46546C67 == 'glTF'
    if (magic != 0x46546C67) {
      throw FormatException('Tệp không phải định dạng glTF 2.0 Binary (magic: 0x${magic.toRadixString(16)}).');
    }

    final version = byteData.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException('Phiên bản glTF không được hỗ trợ: $version (yêu cầu glTF 2.0).');
    }

    final totalLength = byteData.getUint32(8, Endian.little);
    if (bytes.length < totalLength) {
      throw FormatException('Dữ liệu GLB bị cắt cụt.');
    }

    // Chunk 0: JSON metadata
    final jsonChunkLen = byteData.getUint32(12, Endian.little);
    final jsonChunkType = byteData.getUint32(16, Endian.little);
    if (jsonChunkType != 0x4E4F534A) {
      // 'JSON'
      throw FormatException('Chunk đầu tiên của GLB không phải là JSON.');
    }

    final jsonBytes = bytes.sublist(20, 20 + jsonChunkLen);
    final jsonStr = utf8.decode(jsonBytes);
    final Map<String, dynamic> gltf = json.decode(jsonStr) as Map<String, dynamic>;

    // Chunk 1: BIN binary payload
    final binChunkHeaderOffset = 20 + jsonChunkLen;
    Uint8List binBytes = Uint8List(0);
    if (binChunkHeaderOffset + 8 <= bytes.length) {
      final binChunkLen = byteData.getUint32(binChunkHeaderOffset, Endian.little);
      final binChunkType = byteData.getUint32(binChunkHeaderOffset + 4, Endian.little);
      if (binChunkType == 0x004E4942) {
        // 'BIN\0'
        binBytes = bytes.sublist(binChunkHeaderOffset + 8, binChunkHeaderOffset + 8 + binChunkLen);
      }
    }

    final bufferViews = (gltf['bufferViews'] as List<dynamic>? ?? []);
    final accessors = (gltf['accessors'] as List<dynamic>? ?? []);

    Float32List readFloatAccessor(int accIdx, int componentsPerItem) {
      final acc = accessors[accIdx] as Map<String, dynamic>;
      final bvIdx = acc['bufferView'] as int;
      final bv = bufferViews[bvIdx] as Map<String, dynamic>;
      final bvOffset = (bv['byteOffset'] as num? ?? 0).toInt();
      final accOffset = (acc['byteOffset'] as num? ?? 0).toInt();
      final count = (acc['count'] as num).toInt();
      final totalFloats = count * componentsPerItem;
      final byteOffset = bvOffset + accOffset;

      final floatList = Float32List(totalFloats);
      final binByteData = ByteData.sublistView(binBytes, byteOffset, byteOffset + totalFloats * 4);
      for (int i = 0; i < totalFloats; i++) {
        floatList[i] = binByteData.getFloat32(i * 4, Endian.little);
      }
      return floatList;
    }

    Uint16List readIndexAccessor(int accIdx) {
      final acc = accessors[accIdx] as Map<String, dynamic>;
      final bvIdx = acc['bufferView'] as int;
      final bv = bufferViews[bvIdx] as Map<String, dynamic>;
      final bvOffset = (bv['byteOffset'] as num? ?? 0).toInt();
      final accOffset = (acc['byteOffset'] as num? ?? 0).toInt();
      final count = (acc['count'] as num).toInt();
      final compType = (acc['componentType'] as num).toInt();
      final byteOffset = bvOffset + accOffset;

      final idxList = Uint16List(count);
      final binByteData = ByteData.sublistView(binBytes);
      if (compType == 5123) {
        // UNSIGNED_SHORT
        for (int i = 0; i < count; i++) {
          idxList[i] = binByteData.getUint16(byteOffset + i * 2, Endian.little);
        }
      } else if (compType == 5121) {
        // UNSIGNED_BYTE
        for (int i = 0; i < count; i++) {
          idxList[i] = binByteData.getUint8(byteOffset + i);
        }
      } else if (compType == 5125) {
        // UNSIGNED_INT
        for (int i = 0; i < count; i++) {
          idxList[i] = binByteData.getUint32(byteOffset + i * 4, Endian.little);
        }
      }
      return idxList;
    }

    final List<GlbMesh> parsedMeshes = [];
    final Set<String> allMorphNames = {};

    final rawMeshes = (gltf['meshes'] as List<dynamic>? ?? []);
    for (final rawMesh in rawMeshes) {
      final mObj = rawMesh as Map<String, dynamic>;
      final mName = (mObj['name'] as String? ?? 'Mesh_${parsedMeshes.length}');
      final mExtras = (mObj['extras'] as Map<String, dynamic>? ?? {});
      final targetNames = (mExtras['targetNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      for (final t in targetNames) {
        allMorphNames.add(t);
      }

      final prims = (mObj['primitives'] as List<dynamic>? ?? []);
      final List<GlbPrimitive> parsedPrims = [];

      for (final rawPrim in prims) {
        final pMap = rawPrim as Map<String, dynamic>;
        final attrs = pMap['attributes'] as Map<String, dynamic>;

        final posIdx = attrs['POSITION'] as int;
        final positions = readFloatAccessor(posIdx, 3);

        final normIdx = attrs['NORMAL'] as int?;
        final normals = normIdx != null
            ? readFloatAccessor(normIdx, 3)
            : Float32List(positions.length);

        final colIdx = attrs['COLOR_0'] as int?;
        final colors = colIdx != null ? readFloatAccessor(colIdx, 4) : null;

        final idxAcc = pMap['indices'] as int?;
        final Uint16List indices;
        if (idxAcc != null) {
          indices = readIndexAccessor(idxAcc);
        } else {
          indices = Uint16List(positions.length ~/ 3);
          for (int i = 0; i < indices.length; i++) {
            indices[i] = i;
          }
        }

        final List<Float32List> morphDeltas = [];
        final rawTargets = (pMap['targets'] as List<dynamic>? ?? []);
        for (final t in rawTargets) {
          final tMap = t as Map<String, dynamic>;
          final mPosIdx = tMap['POSITION'] as int?;
          if (mPosIdx != null) {
            morphDeltas.add(readFloatAccessor(mPosIdx, 3));
          } else {
            morphDeltas.add(Float32List(positions.length));
          }
        }

        parsedPrims.add(GlbPrimitive(
          positions: positions,
          normals: normals,
          colors: colors,
          indices: indices,
          morphPositionDeltas: morphDeltas,
          morphTargetNames: targetNames,
        ));
      }

      parsedMeshes.add(GlbMesh(
        name: mName,
        primitives: parsedPrims,
      ));
    }

    final rawNodes = (gltf['nodes'] as List<dynamic>? ?? []);
    final List<GlbNode> parsedNodes = [];
    for (int i = 0; i < rawNodes.length; i++) {
      final nMap = rawNodes[i] as Map<String, dynamic>;
      final nName = (nMap['name'] as String? ?? 'Node_$i');
      final tList = (nMap['translation'] as List<dynamic>? ?? [0.0, 0.0, 0.0]);
      final rList = (nMap['rotation'] as List<dynamic>? ?? [0.0, 0.0, 0.0, 1.0]);
      final sList = (nMap['scale'] as List<dynamic>? ?? [1.0, 1.0, 1.0]);
      final mIdx = nMap['mesh'] as int?;
      final cList = (nMap['children'] as List<dynamic>? ?? []).map((e) => (e as num).toInt()).toList();

      parsedNodes.add(GlbNode(
        name: nName,
        translation: Vector3(
          (tList[0] as num).toDouble(),
          (tList[1] as num).toDouble(),
          (tList[2] as num).toDouble(),
        ),
        rotation: Quaternion(
          (rList[0] as num).toDouble(),
          (rList[1] as num).toDouble(),
          (rList[2] as num).toDouble(),
          (rList[3] as num).toDouble(),
        ),
        scale: Vector3(
          (sList[0] as num).toDouble(),
          (sList[1] as num).toDouble(),
          (sList[2] as num).toDouble(),
        ),
        meshIndex: mIdx,
        children: cList,
      ));
    }

    final scenes = (gltf['scenes'] as List<dynamic>? ?? []);
    List<int> rootNodes = [];
    if (scenes.isNotEmpty) {
      final sc0 = scenes[0] as Map<String, dynamic>;
      rootNodes = (sc0['nodes'] as List<dynamic>? ?? [0]).map((e) => (e as num).toInt()).toList();
    } else if (parsedNodes.isNotEmpty) {
      rootNodes = [0];
    }

    return GlbModel(
      name: name,
      meshes: parsedMeshes,
      nodes: parsedNodes,
      rootNodes: rootNodes,
      morphTargetNames: allMorphNames.toList(),
    );
  }
}

