import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:vector_math/vector_math_64.dart';

/// Material metadata parsed from glTF 2.0 / VRM 1.0.
class GlbMaterial {
  final String name;
  final int? baseColorTextureIndex;
  final List<double> baseColorFactor;
  final List<double> fallbackColor;
  final String alphaMode;
  final bool doubleSided;
  final double depthBias;
  final bool isFaceLayer;

  const GlbMaterial({
    required this.name,
    this.baseColorTextureIndex,
    this.baseColorFactor = const [1.0, 1.0, 1.0, 1.0],
    this.fallbackColor = const [0.92, 0.92, 0.94, 1.0],
    this.alphaMode = 'OPAQUE',
    this.doubleSided = false,
    this.depthBias = 0.0,
    this.isFaceLayer = false,
  });
}

/// Skeletal skinning binding (joint node indices + column-major inverse bind matrices).
class GlbSkin {
  final String name;
  final List<int> joints;
  final Float32List inverseBindMatrices;

  const GlbSkin({
    required this.name,
    required this.joints,
    required this.inverseBindMatrices,
  });
}

/// Represents a single 3D primitive containing vertex positions, normals,
/// optional UV texture coordinates, skinning joints/weights, vertex colors,
/// index buffer, and optional morph targets.
class GlbPrimitive {
  final Float32List positions;
  final Float32List normals;
  final Float32List? uvs;
  final Uint16List? joints;
  final Float32List? weights;
  final Float32List? colors;
  final Uint16List indices;
  final int? materialIndex;
  final List<Float32List> morphPositionDeltas;
  final List<String> morphTargetNames;

  const GlbPrimitive({
    required this.positions,
    required this.normals,
    this.uvs,
    this.joints,
    this.weights,
    this.colors,
    required this.indices,
    this.materialIndex,
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
  final int? skinIndex;
  final List<int> children;

  GlbNode({
    required this.name,
    required this.translation,
    required this.rotation,
    required this.scale,
    this.meshIndex,
    this.skinIndex,
    this.children = const [],
  });

  Matrix4 get localTransform {
    return Matrix4.compose(translation, rotation, scale);
  }
}

/// Fully parsed glTF 2.0 Binary (.glb) / VRM humanoid avatar model with
/// support for HD embedded PNG/JPEG textures, UV mapping, Linear Blend Skinning,
/// and 60fps facial morph targets.
class GlbModel {
  final String name;
  final List<GlbMesh> meshes;
  final List<GlbNode> nodes;
  final List<int> rootNodes;
  final List<String> morphTargetNames;
  final List<Uint8List> imageBytes;
  final List<int> textureToImage;
  final List<GlbMaterial> materials;
  final List<GlbSkin> skins;

  const GlbModel({
    required this.name,
    required this.meshes,
    required this.nodes,
    required this.rootNodes,
    this.morphTargetNames = const [],
    this.imageBytes = const [],
    this.textureToImage = const [],
    this.materials = const [],
    this.skins = const [],
  });

  bool get hasMorphTargets => morphTargetNames.isNotEmpty;
  bool get hasSkeleton => nodes.length > 1;
  bool get hasTextures => imageBytes.isNotEmpty && textureToImage.isNotEmpty;

  /// Asynchronously decodes embedded PNG/JPEG texture buffers into GPU [ui.Image]s.
  Future<List<ui.Image?>> decodeTextures() async {
    if (imageBytes.isEmpty) return const [];
    final List<ui.Image?> decoded = List<ui.Image?>.filled(imageBytes.length, null);
    for (int i = 0; i < imageBytes.length; i++) {
      final raw = imageBytes[i];
      if (raw.isEmpty) continue;
      try {
        final codec = await ui.instantiateImageCodec(raw);
        final frame = await codec.getNextFrame();
        decoded[i] = frame.image;
      } catch (_) {
        decoded[i] = null;
      }
    }
    return decoded;
  }

  /// Fast binary glTF 2.0 / VRM parser reading directly from in-memory byte buffer.
  factory GlbModel.fromBytes(Uint8List bytes, {String name = 'Avatar'}) {
    final byteData = ByteData.sublistView(bytes);
    if (bytes.length < 20) {
      throw const FormatException('Tệp GLB quá nhỏ hoặc không hợp lệ.');
    }

    final magic = byteData.getUint32(0, Endian.little);
    // 0x46546C67 == 'glTF'
    if (magic != 0x46546C67) {
      throw FormatException(
        'Tệp không phải định dạng glTF 2.0 Binary (magic: 0x${magic.toRadixString(16)}).',
      );
    }

    final version = byteData.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException(
        'Phiên bản glTF không được hỗ trợ: $version (yêu cầu glTF 2.0).',
      );
    }

    final totalLength = byteData.getUint32(8, Endian.little);
    if (bytes.length < totalLength) {
      throw const FormatException('Dữ liệu GLB bị cắt cụt.');
    }

    // Chunk 0: JSON metadata
    final jsonChunkLen = byteData.getUint32(12, Endian.little);
    final jsonChunkType = byteData.getUint32(16, Endian.little);
    if (jsonChunkType != 0x4E4F534A) {
      throw const FormatException('Chunk đầu tiên của GLB không phải là JSON.');
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
        binBytes = Uint8List.sublistView(
          bytes,
          binChunkHeaderOffset + 8,
          binChunkHeaderOffset + 8 + binChunkLen,
        );
      }
    }

    final bufferViews = (gltf['bufferViews'] as List<dynamic>? ?? []);
    final accessors = (gltf['accessors'] as List<dynamic>? ?? []);
    final binByteData = ByteData.sublistView(binBytes);

    Float32List readFloatAccessor(int accIdx, int componentsPerItem) {
      final acc = accessors[accIdx] as Map<String, dynamic>;
      final bvIdx = acc['bufferView'] as int;
      final bv = bufferViews[bvIdx] as Map<String, dynamic>;
      final bvOffset = (bv['byteOffset'] as num? ?? 0).toInt();
      final accOffset = (acc['byteOffset'] as num? ?? 0).toInt();
      final count = (acc['count'] as num).toInt();
      final stride = (bv['byteStride'] as num?)?.toInt() ?? (componentsPerItem * 4);
      final baseOffset = bvOffset + accOffset;

      final floatList = Float32List(count * componentsPerItem);
      int outIdx = 0;
      for (int i = 0; i < count; i++) {
        final itemOffset = baseOffset + i * stride;
        for (int c = 0; c < componentsPerItem; c++) {
          floatList[outIdx++] =
              binByteData.getFloat32(itemOffset + c * 4, Endian.little);
        }
      }
      return floatList;
    }

    Uint16List readUint16VecAccessor(int accIdx, int componentsPerItem) {
      final acc = accessors[accIdx] as Map<String, dynamic>;
      final bvIdx = acc['bufferView'] as int;
      final bv = bufferViews[bvIdx] as Map<String, dynamic>;
      final bvOffset = (bv['byteOffset'] as num? ?? 0).toInt();
      final accOffset = (acc['byteOffset'] as num? ?? 0).toInt();
      final count = (acc['count'] as num).toInt();
      final compType = (acc['componentType'] as num).toInt();
      final compBytes = compType == 5121 ? 1 : (compType == 5123 ? 2 : 4);
      final stride =
          (bv['byteStride'] as num?)?.toInt() ?? (componentsPerItem * compBytes);
      final baseOffset = bvOffset + accOffset;

      final out = Uint16List(count * componentsPerItem);
      int outIdx = 0;
      for (int i = 0; i < count; i++) {
        final itemOffset = baseOffset + i * stride;
        for (int c = 0; c < componentsPerItem; c++) {
          final off = itemOffset + c * compBytes;
          if (compType == 5121) {
            out[outIdx++] = binByteData.getUint8(off);
          } else if (compType == 5123) {
            out[outIdx++] = binByteData.getUint16(off, Endian.little);
          } else {
            out[outIdx++] = binByteData.getUint32(off, Endian.little);
          }
        }
      }
      return out;
    }

    Uint16List readIndexAccessor(int accIdx) {
      return readUint16VecAccessor(accIdx, 1);
    }

    // 1. Parse Images & Textures
    final rawImages = (gltf['images'] as List<dynamic>? ?? []);
    final List<Uint8List> parsedImageBytes = [];
    for (final rawImg in rawImages) {
      final imMap = rawImg as Map<String, dynamic>;
      final bvIdx = (imMap['bufferView'] as num?)?.toInt();
      if (bvIdx != null && bvIdx >= 0 && bvIdx < bufferViews.length) {
        final bv = bufferViews[bvIdx] as Map<String, dynamic>;
        final off = (bv['byteOffset'] as num? ?? 0).toInt();
        final len = (bv['byteLength'] as num? ?? 0).toInt();
        if (off >= 0 && off + len <= binBytes.length) {
          parsedImageBytes.add(Uint8List.sublistView(binBytes, off, off + len));
          continue;
        }
      }
      parsedImageBytes.add(Uint8List(0));
    }

    final rawTextures = (gltf['textures'] as List<dynamic>? ?? []);
    final List<int> parsedTexToImg = [];
    for (final rawTex in rawTextures) {
      final tMap = rawTex as Map<String, dynamic>;
      parsedTexToImg.add((tMap['source'] as num? ?? -1).toInt());
    }

    // 2. Parse Materials
    final rawMaterials = (gltf['materials'] as List<dynamic>? ?? []);
    final List<GlbMaterial> parsedMaterials = [];
    for (int i = 0; i < rawMaterials.length; i++) {
      final matMap = rawMaterials[i] as Map<String, dynamic>;
      final matName = matMap['name'] as String? ?? 'Mat_$i';
      final pbr = matMap['pbrMetallicRoughness'] as Map<String, dynamic>? ?? {};
      final bct = pbr['baseColorTexture'] as Map<String, dynamic>?;
      final texIdx = (bct?['index'] as num?)?.toInt();
      final bcfRaw = pbr['baseColorFactor'] as List<dynamic>?;
      final bcf = bcfRaw != null && bcfRaw.length >= 4
          ? bcfRaw.map((e) => (e as num).toDouble()).toList()
          : const [1.0, 1.0, 1.0, 1.0];
      final extras = matMap['extras'] as Map<String, dynamic>? ?? {};
      final fbRaw = extras['fallbackColor'] as List<dynamic>?;
      final fallbackCol = fbRaw != null && fbRaw.length >= 4
          ? fbRaw.map((e) => (e as num).toDouble()).toList()
          : bcf;
      final depthBias = (extras['depthBias'] as num? ?? 0.0).toDouble();
      final isFaceLayer = extras['isFaceLayer'] == true ||
          matName.toLowerCase().contains('face') ||
          matName.toLowerCase().contains('eye');

      parsedMaterials.add(
        GlbMaterial(
          name: matName,
          baseColorTextureIndex: texIdx,
          baseColorFactor: bcf,
          fallbackColor: fallbackCol,
          alphaMode: (matMap['alphaMode'] as String? ?? 'OPAQUE').toUpperCase(),
          doubleSided: matMap['doubleSided'] == true,
          depthBias: depthBias,
          isFaceLayer: isFaceLayer,
        ),
      );
    }

    // 3. Parse Skins
    final rawSkins = (gltf['skins'] as List<dynamic>? ?? []);
    final List<GlbSkin> parsedSkins = [];
    for (int i = 0; i < rawSkins.length; i++) {
      final sMap = rawSkins[i] as Map<String, dynamic>;
      final jointsList = (sMap['joints'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList();
      final ibmAcc = (sMap['inverseBindMatrices'] as num?)?.toInt();
      final Float32List ibms;
      if (ibmAcc != null) {
        ibms = readFloatAccessor(ibmAcc, 16);
      } else {
        ibms = Float32List(jointsList.length * 16);
        for (int j = 0; j < jointsList.length; j++) {
          ibms[j * 16 + 0] = 1.0;
          ibms[j * 16 + 5] = 1.0;
          ibms[j * 16 + 10] = 1.0;
          ibms[j * 16 + 15] = 1.0;
        }
      }
      parsedSkins.add(
        GlbSkin(
          name: sMap['name'] as String? ?? 'Skin_$i',
          joints: jointsList,
          inverseBindMatrices: ibms,
        ),
      );
    }

    // 4. Parse Meshes & Primitives
    final List<GlbMesh> parsedMeshes = [];
    final Set<String> allMorphNames = {};

    final rawMeshes = (gltf['meshes'] as List<dynamic>? ?? []);
    for (final rawMesh in rawMeshes) {
      final mObj = rawMesh as Map<String, dynamic>;
      final mName = (mObj['name'] as String? ?? 'Mesh_${parsedMeshes.length}');
      final mExtras = (mObj['extras'] as Map<String, dynamic>? ?? {});
      List<String> meshTargetNames = (mExtras['targetNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      final prims = (mObj['primitives'] as List<dynamic>? ?? []);
      final List<GlbPrimitive> parsedPrims = [];

      for (final rawPrim in prims) {
        final pMap = rawPrim as Map<String, dynamic>;
        final pExtras = (pMap['extras'] as Map<String, dynamic>? ?? {});
        final primTargetNames = meshTargetNames.isNotEmpty
            ? meshTargetNames
            : (pExtras['targetNames'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();

        for (final t in primTargetNames) {
          allMorphNames.add(t);
        }

        final attrs = pMap['attributes'] as Map<String, dynamic>;

        final posIdx = attrs['POSITION'] as int;
        final positions = readFloatAccessor(posIdx, 3);

        final normIdx = attrs['NORMAL'] as int?;
        final normals = normIdx != null
            ? readFloatAccessor(normIdx, 3)
            : Float32List(positions.length);

        final uvIdx = attrs['TEXCOORD_0'] as int?;
        final uvs = uvIdx != null ? readFloatAccessor(uvIdx, 2) : null;

        final jointsIdx = attrs['JOINTS_0'] as int?;
        final joints =
            jointsIdx != null ? readUint16VecAccessor(jointsIdx, 4) : null;

        final weightsIdx = attrs['WEIGHTS_0'] as int?;
        final weights =
            weightsIdx != null ? readFloatAccessor(weightsIdx, 4) : null;

        final colIdx = attrs['COLOR_0'] as int?;
        final colors = colIdx != null ? readFloatAccessor(colIdx, 4) : null;

        final matIdx = (pMap['material'] as num?)?.toInt();

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

        parsedPrims.add(
          GlbPrimitive(
            positions: positions,
            normals: normals,
            uvs: uvs,
            joints: joints,
            weights: weights,
            colors: colors,
            indices: indices,
            materialIndex: matIdx,
            morphPositionDeltas: morphDeltas,
            morphTargetNames: primTargetNames,
          ),
        );
      }

      parsedMeshes.add(
        GlbMesh(
          name: mName,
          primitives: parsedPrims,
        ),
      );
    }

    // 5. Parse Scene Nodes
    final rawNodes = (gltf['nodes'] as List<dynamic>? ?? []);
    final List<GlbNode> parsedNodes = [];
    for (int i = 0; i < rawNodes.length; i++) {
      final nMap = rawNodes[i] as Map<String, dynamic>;
      final nName = (nMap['name'] as String? ?? 'Node_$i');
      final tList = (nMap['translation'] as List<dynamic>? ?? [0.0, 0.0, 0.0]);
      final rList =
          (nMap['rotation'] as List<dynamic>? ?? [0.0, 0.0, 0.0, 1.0]);
      final sList = (nMap['scale'] as List<dynamic>? ?? [1.0, 1.0, 1.0]);
      final mIdx = (nMap['mesh'] as num?)?.toInt();
      final sIdx = (nMap['skin'] as num?)?.toInt();
      final cList = (nMap['children'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList();

      parsedNodes.add(
        GlbNode(
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
          skinIndex: sIdx,
          children: cList,
        ),
      );
    }

    final scenes = (gltf['scenes'] as List<dynamic>? ?? []);
    List<int> rootNodes = [];
    if (scenes.isNotEmpty) {
      final sc0 = scenes[0] as Map<String, dynamic>;
      rootNodes = (sc0['nodes'] as List<dynamic>? ?? [0])
          .map((e) => (e as num).toInt())
          .toList();
    } else if (parsedNodes.isNotEmpty) {
      rootNodes = [0];
    }

    return GlbModel(
      name: name,
      meshes: parsedMeshes,
      nodes: parsedNodes,
      rootNodes: rootNodes,
      morphTargetNames: allMorphNames.toList(),
      imageBytes: parsedImageBytes,
      textureToImage: parsedTexToImg,
      materials: parsedMaterials,
      skins: parsedSkins,
    );
  }
}
