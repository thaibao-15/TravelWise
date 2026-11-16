import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../models/glb_model.dart';
import '../../services/avatar_animation_service.dart';

/// Reusable zero-GC scratch buffer pool for 3D glTF rasterization.
class _GlbBufferPool {
  Float32List triDepths = Float32List(16384);
  Float32List triScreenXY = Float32List(16384 * 6);
  Float32List triUvXY = Float32List(16384 * 6);
  Int32List triColors = Int32List(16384 * 3);
  Int32List triTexImg = Int32List(16384);
  Int32List drawOrder = Int32List(16384);

  // Per-vertex scratch buffers
  Float32List screenX = Float32List(4096);
  Float32List screenY = Float32List(4096);
  Float32List camDepth = Float32List(4096);
  Uint8List validVert = Uint8List(4096);
  Int32List vertColors = Int32List(4096);
  Float32List morphedPos = Float32List(4096 * 3);

  // Batch scratch buffers
  Float32List batchPos = Float32List(16384 * 6);
  Float32List batchUv = Float32List(16384 * 6);
  Int32List batchCol = Int32List(16384 * 3);

  // Skin joint matrices
  final List<Float32List> skinJointMatrices = [];

  // World transforms
  final List<vm.Matrix4> worldTransforms = [];

  void ensureTriCapacity(int required) {
    if (triDepths.length < required) {
      int next = triDepths.length * 2;
      while (next < required) {
        next *= 2;
      }
      triDepths = Float32List(next);
      triScreenXY = Float32List(next * 6);
      triUvXY = Float32List(next * 6);
      triColors = Int32List(next * 3);
      triTexImg = Int32List(next);
      drawOrder = Int32List(next);
      batchPos = Float32List(next * 6);
      batchUv = Float32List(next * 6);
      batchCol = Int32List(next * 3);
    }
  }

  void ensureVertCapacity(int required) {
    if (screenX.length < required) {
      int next = screenX.length * 2;
      while (next < required) {
        next *= 2;
      }
      screenX = Float32List(next);
      screenY = Float32List(next);
      camDepth = Float32List(next);
      validVert = Uint8List(next);
      vertColors = Int32List(next);
      morphedPos = Float32List(next * 3);
    }
  }

  void ensureSkinCapacity(int skinIndex, int jointCount) {
    while (skinJointMatrices.length <= skinIndex) {
      skinJointMatrices.add(Float32List(0));
    }
    final req = jointCount * 16;
    if (skinJointMatrices[skinIndex].length < req) {
      skinJointMatrices[skinIndex] = Float32List(req);
    }
  }

  void ensureNodeCapacity(int count) {
    while (worldTransforms.length < count) {
      worldTransforms.add(vm.Matrix4.identity());
    }
  }
}

/// High-definition hardware-accelerated 3D glTF / VRM rasterizer using
/// batched `ui.Vertices.raw` + `ui.ImageShader` trilinear mipmapping.
///
/// Performance optimizations:
/// - Zero-GC global scratch buffers across frames (0 heap churn)
/// - Expando-cached `ui.ImageShader` paints (0 C++ shader reconstructions)
/// - Non-allocating in-place QuickSort on primitive typed arrays
/// - Direct fast-path morph target lookup without Map allocations
/// - Ultra-fast Fresnel multiplication replacing expensive transcendental `pow`
class Glb3dPainter extends CustomPainter {
  static final Float64List _identityShaderMatrix = Float64List.fromList(<double>[
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
  ]);

  static final _GlbBufferPool _pool = _GlbBufferPool();
  static final Expando<Paint> _shaderPaintCache = Expando<Paint>();

  static final Paint _untexturedPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..color = const Color(0xFFFFFFFF);

  static Paint _getShaderPaint(ui.Image img) {
    var p = _shaderPaintCache[img];
    if (p == null) {
      p = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.medium
        ..shader = ui.ImageShader(
          img,
          TileMode.repeated,
          TileMode.repeated,
          _identityShaderMatrix,
          filterQuality: FilterQuality.medium,
        );
      _shaderPaintCache[img] = p;
    }
    return p;
  }

  final GlbModel model;
  final List<ui.Image?>? textures;
  final AvatarFrameState frame;
  final double orbitYaw;
  final double orbitPitch;
  final double zoom;
  final double cameraDistance;
  final double targetY;

  Glb3dPainter({
    required this.model,
    this.textures,
    required this.frame,
    required this.orbitYaw,
    required this.orbitPitch,
    required this.zoom,
    this.cameraDistance = 1.14,
    this.targetY = 1.18,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (model.nodes.isEmpty || size.width <= 0 || size.height <= 0) return;

    final double screenW = size.width;
    final double screenH = size.height;
    final double cx = screenW * 0.5;
    final double cy = screenH * 0.5;
    final double fovScale = math.min(screenW, screenH) * 1.24 * zoom;

    // 1. View rotation from user orbit
    final vm.Matrix4 viewRot = vm.Matrix4.identity()
      ..rotate(vm.Vector3(0, 1, 0), orbitYaw)
      ..rotate(vm.Vector3(1, 0, 0), orbitPitch);

    // 2. Hierarchical bone world transforms (composed cleanly on top of rest rotations)
    _pool.ensureNodeCapacity(model.nodes.length);
    final List<vm.Matrix4> worldTransforms = _pool.worldTransforms;

    final bool isSkinnedAvatar = model.skins.isNotEmpty;

    void evaluateNode(int nodeIdx, vm.Matrix4 parentTransform) {
      final node = model.nodes[nodeIdx];
      final vm.Vector3 trans = node.translation.clone();
      vm.Quaternion rot = node.rotation.clone();
      final name = node.name;

      if (name == 'Head' || name == 'J_Bip_C_Head') {
        final qPitch =
            vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -frame.headPitch * 0.85);
        final qYaw = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), frame.headYaw);
        final qRoll = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), frame.headRoll);
        rot = rot * (qYaw * qPitch * qRoll);
      } else if (name == 'Neck' || name == 'J_Bip_C_Neck') {
        final qPitch =
            vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -frame.headPitch * 0.25);
        final qYaw =
            vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), frame.headYaw * 0.30);
        rot = rot * (qYaw * qPitch);
      } else if (name == 'Chest' || name == 'J_Bip_C_Chest') {
        trans.y += frame.chestBreath;
        final qPitch =
            vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -frame.chestPitch);
        final qRoll =
            vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), frame.chestRoll);
        rot = rot * (qPitch * qRoll);
      } else if (name == 'LeftUpperArm' || name == 'J_Bip_L_UpperArm') {
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          -frame.leftArmPitch * (isSkinnedAvatar ? 0.55 : 1.0),
        );
        final qRoll = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          frame.leftArmRoll * 0.65,
        );
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          frame.leftArmYaw * 0.65,
        );
        rot = (qPitch * qRoll * qYaw) * rot;
      } else if (name == 'LeftForeArm' || name == 'J_Bip_L_LowerArm') {
        final double autoElbow =
            isSkinnedAvatar ? (frame.leftArmPitch.clamp(0.0, 0.7) * 0.75) : 0.0;
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          -(frame.leftForeArmPitch + autoElbow),
        );
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          frame.leftForeArmYaw,
        );
        rot = (qPitch * qYaw) * rot;
      } else if (name == 'RightUpperArm' || name == 'J_Bip_R_UpperArm') {
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          -frame.rightArmPitch * (isSkinnedAvatar ? 0.55 : 1.0),
        );
        final qRoll = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          frame.rightArmRoll * 0.65,
        );
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          frame.rightArmYaw * 0.65,
        );
        rot = (qPitch * qRoll * qYaw) * rot;
      } else if (name == 'RightForeArm' || name == 'J_Bip_R_LowerArm') {
        final double autoElbow =
            isSkinnedAvatar ? (frame.rightArmPitch.clamp(0.0, 0.7) * 0.75) : 0.0;
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          -(frame.rightForeArmPitch + autoElbow),
        );
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          frame.rightForeArmYaw,
        );
        rot = (qPitch * qYaw) * rot;
      }

      final localMat = vm.Matrix4.compose(trans, rot, node.scale);
      final worldMat = parentTransform * localMat;
      worldTransforms[nodeIdx] = worldMat;

      for (final childIdx in node.children) {
        if (childIdx >= 0 && childIdx < model.nodes.length) {
          evaluateNode(childIdx, worldMat);
        }
      }
    }

    for (final r in model.rootNodes) {
      if (r >= 0 && r < model.nodes.length) {
        evaluateNode(r, viewRot);
      }
    }

    // 3. Precompute Linear Blend Skinning joint matrices using pooled flat arrays
    if (model.skins.isNotEmpty) {
      final vm.Matrix4 ibmMat = vm.Matrix4.identity();
      final vm.Matrix4 combined = vm.Matrix4.identity();
      for (int sIdx = 0; sIdx < model.skins.length; sIdx++) {
        final skin = model.skins[sIdx];
        final jCount = skin.joints.length;
        _pool.ensureSkinCapacity(sIdx, jCount);
        final flatMats = _pool.skinJointMatrices[sIdx];
        final ibms = skin.inverseBindMatrices;
        for (int j = 0; j < jCount; j++) {
          final jointNodeIdx = skin.joints[j];
          final ibmBase = j * 16;
          final ibmStorage = ibmMat.storage;
          for (int k = 0; k < 16; k++) {
            ibmStorage[k] = ibms[ibmBase + k];
          }
          combined.setFrom(worldTransforms[jointNodeIdx]);
          combined.multiply(ibmMat);
          final cStorage = combined.storage;
          for (int k = 0; k < 16; k++) {
            flatMats[ibmBase + k] = cStorage[k];
          }
        }
      }
    }

    // Studio Anime MToon Lighting vectors
    final vm.Vector3 keyLight = vm.Vector3(0.26, 0.38, 0.88)..normalize();
    final vm.Vector3 fillLight = vm.Vector3(-0.34, 0.22, 0.60)..normalize();
    final double keyX = keyLight.x, keyY = keyLight.y, keyZ = keyLight.z;
    final double fillX = fillLight.x, fillY = fillLight.y, fillZ = fillLight.z;

    // Damp smile slightly when vowels open wide so blended VRM morphs stay crisp
    final double vowelSum =
        (frame.visemeAa + frame.visemeOh + frame.visemeEe).clamp(0.0, 1.0);
    final double dampedSmile = frame.smileWeight * (1.0 - vowelSum * 0.72);

    // Count upper bound of triangles for pooled buffers
    int maxTotalTris = 0;
    for (final node in model.nodes) {
      final mIdx = node.meshIndex;
      if (mIdx != null && mIdx >= 0 && mIdx < model.meshes.length) {
        for (final prim in model.meshes[mIdx].primitives) {
          maxTotalTris += prim.triangleCount;
        }
      }
    }
    if (maxTotalTris == 0) return;

    _pool.ensureTriCapacity(maxTotalTris);
    final Float32List triDepths = _pool.triDepths;
    final Float32List triScreenXY = _pool.triScreenXY;
    final Float32List triUvXY = _pool.triUvXY;
    final Int32List triColors = _pool.triColors;
    final Int32List triTexImg = _pool.triTexImg;
    int emittedTris = 0;

    // 4. Transform, shade, cull, and emit visible triangles
    for (int nIdx = 0; nIdx < model.nodes.length; nIdx++) {
      final node = model.nodes[nIdx];
      final meshIdx = node.meshIndex;
      if (meshIdx == null || meshIdx < 0 || meshIdx >= model.meshes.length) {
        continue;
      }

      final mesh = model.meshes[meshIdx];
      final int? skinIdx = node.skinIndex;
      final Float32List? jointMats =
          (skinIdx != null && skinIdx >= 0 && skinIdx < _pool.skinJointMatrices.length)
              ? _pool.skinJointMatrices[skinIdx]
              : null;

      final vm.Matrix4 worldMat = worldTransforms[nIdx];
      final Float64List wStorage = worldMat.storage;
      final vm.Matrix3 normalMat = vm.Matrix3.identity();
      if (jointMats == null) {
        worldMat.copyRotation(normalMat);
        normalMat.invert();
        normalMat.transpose();
      }
      final Float64List nStorage = normalMat.storage;

      final meshNameLower = mesh.name.toLowerCase();

      for (final prim in mesh.primitives) {
        final int vertCount = prim.vertexCount;
        if (vertCount == 0) continue;

        final GlbMaterial? mat = (prim.materialIndex != null &&
                prim.materialIndex! >= 0 &&
                prim.materialIndex! < model.materials.length)
            ? model.materials[prim.materialIndex!]
            : null;

        int resolvedImgIdx = -1;
        ui.Image? activeImage;
        if (mat?.baseColorTextureIndex != null && textures != null) {
          final tIdx = mat!.baseColorTextureIndex!;
          if (tIdx >= 0 && tIdx < model.textureToImage.length) {
            final imIdx = model.textureToImage[tIdx];
            if (imIdx >= 0 &&
                imIdx < textures!.length &&
                textures![imIdx] != null) {
              resolvedImgIdx = imIdx;
              activeImage = textures![imIdx];
            }
          }
        }

        final bool hasGpuTex = activeImage != null && prim.uvs != null;
        final double imgW = activeImage?.width.toDouble() ?? 1.0;
        final double imgH = activeImage?.height.toDouble() ?? 1.0;
        final bool doubleSided = mat?.doubleSided ?? false;
        final bool isFaceLayer =
            mat?.isFaceLayer ?? meshNameLower.contains('face');
        final bool isPureUnlitEye = mat != null &&
            (mat.name.contains('EyeHighlight') ||
                mat.name.contains('EyeIris') ||
                mat.name.contains('EyeWhite'));
        final double depthBias =
            mat?.depthBias ?? (isFaceLayer ? 0.0012 : 0.0);

        _pool.ensureVertCapacity(vertCount);
        final Float32List screenX = _pool.screenX;
        final Float32List screenY = _pool.screenY;
        final Float32List camDepth = _pool.camDepth;
        final Uint8List validVert = _pool.validVert;
        final Int32List vertColors = _pool.vertColors;

        // Apply active morph targets (blend shapes) using zero-GC scratch buffer
        final Float32List basePos = prim.positions;
        Float32List posSrc = basePos;
        if (prim.morphPositionDeltas.isNotEmpty &&
            prim.morphTargetNames.isNotEmpty) {
          bool hasMorph = false;
          final int posLen = basePos.length;
          final Float32List morphed = _pool.morphedPos;

          for (int mI = 0; mI < prim.morphPositionDeltas.length; mI++) {
            final String tName =
                mI < prim.morphTargetNames.length ? prim.morphTargetNames[mI] : '';
            final double weight = (tName == 'smile' || tName == 'Joy' || tName == 'Fcl_MTH_Fun')
                ? dampedSmile
                : frame.getMorphWeight(tName);
            if (weight.abs() > 0.001) {
              if (!hasMorph) {
                morphed.setRange(0, posLen, basePos);
                hasMorph = true;
              }
              final Float32List deltas = prim.morphPositionDeltas[mI];
              for (int i = 0; i < posLen; i++) {
                morphed[i] += deltas[i] * weight;
              }
            }
          }
          if (hasMorph) posSrc = morphed;
        }

        final Float32List baseNorm = prim.normals;
        final Float32List? baseCol = prim.colors;
        final Float32List? baseUv = prim.uvs;
        final Uint16List? joints = prim.joints;
        final Float32List? weights = prim.weights;

        final bool useSkin =
            jointMats != null && joints != null && weights != null;
        final int jointMatCount =
            jointMats != null ? (jointMats.length ~/ 16) : 0;

        final List<double> fbCol =
            mat?.fallbackColor ?? const [0.95, 0.95, 0.96, 1.0];

        for (int i = 0; i < vertCount; i++) {
          final int i3 = i * 3;
          final double px = posSrc[i3];
          final double py = posSrc[i3 + 1];
          final double pz = posSrc[i3 + 2];

          final double nx0 = baseNorm[i3];
          final double ny0 = baseNorm[i3 + 1];
          final double nz0 = baseNorm[i3 + 2];

          double vx, vy, vz;
          double vnx, vny, vnz;

          if (useSkin) {
            final int i4 = i * 4;
            vx = 0.0;
            vy = 0.0;
            vz = 0.0;
            vnx = 0.0;
            vny = 0.0;
            vnz = 0.0;

            for (int k = 0; k < 4; k++) {
              final double w = weights[i4 + k];
              if (w <= 0.0001) continue;
              int jIdx = joints[i4 + k];
              if (jIdx >= jointMatCount) jIdx = 0;
              final int mOff = jIdx * 16;

              final double m0 = jointMats[mOff];
              final double m1 = jointMats[mOff + 1];
              final double m2 = jointMats[mOff + 2];
              final double m4 = jointMats[mOff + 4];
              final double m5 = jointMats[mOff + 5];
              final double m6 = jointMats[mOff + 6];
              final double m8 = jointMats[mOff + 8];
              final double m9 = jointMats[mOff + 9];
              final double m10 = jointMats[mOff + 10];
              final double m12 = jointMats[mOff + 12];
              final double m13 = jointMats[mOff + 13];
              final double m14 = jointMats[mOff + 14];

              vx += (m0 * px + m4 * py + m8 * pz + m12) * w;
              vy += (m1 * px + m5 * py + m9 * pz + m13) * w;
              vz += (m2 * px + m6 * py + m10 * pz + m14) * w;

              vnx += (m0 * nx0 + m4 * ny0 + m8 * nz0) * w;
              vny += (m1 * nx0 + m5 * ny0 + m9 * nz0) * w;
              vnz += (m2 * nx0 + m6 * ny0 + m10 * nz0) * w;
            }
          } else {
            vx = wStorage[0] * px + wStorage[4] * py + wStorage[8] * pz + wStorage[12];
            vy = wStorage[1] * px + wStorage[5] * py + wStorage[9] * pz + wStorage[13];
            vz = wStorage[2] * px + wStorage[6] * py + wStorage[10] * pz + wStorage[14];

            vnx = nStorage[0] * nx0 + nStorage[3] * ny0 + nStorage[6] * nz0;
            vny = nStorage[1] * nx0 + nStorage[4] * ny0 + nStorage[7] * nz0;
            vnz = nStorage[2] * nx0 + nStorage[5] * ny0 + nStorage[8] * nz0;
          }

          final double z = cameraDistance - vz;
          camDepth[i] = z;
          if (z >= 0.08) {
            final double invZ = fovScale / z;
            screenX[i] = cx + vx * invZ;
            screenY[i] = cy - (vy - targetY) * invZ;
            validVert[i] = 1;
          } else {
            validVert[i] = 0;
          }

          final double nLen = math.sqrt(vnx * vnx + vny * vny + vnz * vnz);
          if (nLen > 1e-6) {
            final double invN = 1.0 / nLen;
            vnx *= invN;
            vny *= invN;
            vnz *= invN;
          } else {
            vnx = 0.0;
            vny = 0.0;
            vnz = 1.0;
          }

          // For double-sided hair/cloth, orient normal toward viewer for clean interior lighting
          if (doubleSided && vnz < 0.0) {
            vnx = -vnx;
            vny = -vny;
            vnz = -vnz;
          }

          final double nDotKey =
              (vnx * keyX + vny * keyY + vnz * keyZ).clamp(0.0, 1.0);
          final double nDotFill =
              (vnx * fillX + vny * fillY + vnz * fillZ).clamp(0.0, 1.0);

          double finalR, finalG, finalB;

          if (hasGpuTex) {
            if (isPureUnlitEye) {
              finalR = 1.0;
              finalG = 1.0;
              finalB = 1.0;
            } else if (isFaceLayer) {
              final double toonT =
                  ((nDotKey * 0.75 + nDotFill * 0.35 - 0.18) / 0.45)
                      .clamp(0.0, 1.0);
              final double smoothT = toonT * toonT * (3.0 - 2.0 * toonT);
              finalR = 0.945 + 0.055 * smoothT;
              finalG = 0.915 + 0.085 * smoothT;
              finalB = 0.925 + 0.075 * smoothT;
            } else {
              final double sky = (0.5 + 0.5 * vny).clamp(0.0, 1.0);
              final double rawShade =
                  nDotKey * 0.72 + nDotFill * 0.28 + sky * 0.15;
              final double toonT = ((rawShade - 0.22) / 0.48).clamp(0.0, 1.0);
              final double smoothT = toonT * toonT * (3.0 - 2.0 * toonT);
              final double rimVal = (1.0 - vnz.abs()).clamp(0.0, 1.0);
              final double rim = rimVal * rimVal * rimVal * 0.08;
              finalR = (0.80 + 0.20 * smoothT + rim * 0.6).clamp(0.0, 1.0);
              finalG = (0.81 + 0.19 * smoothT + rim * 0.8).clamp(0.0, 1.0);
              finalB = (0.85 + 0.15 * smoothT + rim * 1.0).clamp(0.0, 1.0);
            }
          } else {
            double cr = fbCol[0], cg = fbCol[1], cb = fbCol[2];
            if (baseCol != null) {
              final int c4 = i * 4;
              cr = baseCol[c4];
              cg = baseCol[c4 + 1];
              cb = baseCol[c4 + 2];
            }
            if (isFaceLayer) {
              final double faceLight =
                  0.93 + 0.09 * (nDotKey * 0.72 + nDotFill * 0.28);
              finalR = (cr * faceLight).clamp(0.0, 1.0);
              finalG = (cg * faceLight).clamp(0.0, 1.0);
              finalB = (cb * faceLight).clamp(0.0, 1.0);
            } else {
              final double skyAmbient = (0.50 + 0.50 * vny).clamp(0.0, 1.0);
              final double ambient = 0.42 + 0.16 * skyAmbient;
              final double diffuse = 0.44 * nDotKey + 0.22 * nDotFill;
              final double lum = cr * 0.299 + cg * 0.587 + cb * 0.114;
              final double darkLift = math.max(0.0, 1.0 - lum * 2.2) * 0.30;
              final double totalLight = ambient + diffuse + darkLift;
              final double rimVal = (1.0 - vnz.abs()).clamp(0.0, 1.0);
              final double rim = rimVal * rimVal * rimVal * 0.18;
              finalR = (cr * totalLight + rim * 0.25).clamp(0.0, 1.0);
              finalG = (cg * totalLight + rim * 0.40).clamp(0.0, 1.0);
              finalB = (cb * totalLight + rim * 0.55).clamp(0.0, 1.0);
            }
          }

          final int ir = (finalR * 255.0 + 0.5).toInt().clamp(0, 255);
          final int ig = (finalG * 255.0 + 0.5).toInt().clamp(0, 255);
          final int ib = (finalB * 255.0 + 0.5).toInt().clamp(0, 255);
          vertColors[i] = (0xFF << 24) | (ir << 16) | (ig << 8) | ib;
        }

        final Uint16List indices = prim.indices;
        final int triCount = indices.length ~/ 3;
        for (int t = 0; t < triCount; t++) {
          final int t3 = t * 3;
          final int i0 = indices[t3];
          final int i1 = indices[t3 + 1];
          final int i2 = indices[t3 + 2];

          if (validVert[i0] == 0 || validVert[i1] == 0 || validVert[i2] == 0) {
            continue;
          }

          final double x0 = screenX[i0], y0 = screenY[i0];
          final double x1 = screenX[i1], y1 = screenY[i1];
          final double x2 = screenX[i2], y2 = screenY[i2];

          // 2D Viewport frustum culling
          if (x0 < 0.0 && x1 < 0.0 && x2 < 0.0) continue;
          if (x0 > screenW && x1 > screenW && x2 > screenW) continue;
          if (y0 < 0.0 && y1 < 0.0 && y2 < 0.0) continue;
          if (y0 > screenH && y1 > screenH && y2 > screenH) continue;

          // Backface culling
          final double cross = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
          if (!doubleSided && cross >= 0.0) continue;
          if (cross.abs() < 1e-4) continue;

          final int outIdx = emittedTris++;
          final double backBias = (doubleSided && cross >= 0.0) ? 0.0005 : 0.0;
          triDepths[outIdx] =
              (camDepth[i0] + camDepth[i1] + camDepth[i2]) * (1.0 / 3.0) +
                  depthBias +
                  backBias;

          final int p6 = outIdx * 6;
          triScreenXY[p6] = x0;
          triScreenXY[p6 + 1] = y0;
          triScreenXY[p6 + 2] = x1;
          triScreenXY[p6 + 3] = y1;
          triScreenXY[p6 + 4] = x2;
          triScreenXY[p6 + 5] = y2;

          if (hasGpuTex && baseUv != null) {
            final int u0 = i0 * 2, u1 = i1 * 2, u2 = i2 * 2;
            triUvXY[p6] = baseUv[u0] * imgW;
            triUvXY[p6 + 1] = baseUv[u0 + 1] * imgH;
            triUvXY[p6 + 2] = baseUv[u1] * imgW;
            triUvXY[p6 + 3] = baseUv[u1 + 1] * imgH;
            triUvXY[p6 + 4] = baseUv[u2] * imgW;
            triUvXY[p6 + 5] = baseUv[u2 + 1] * imgH;
            triTexImg[outIdx] = resolvedImgIdx;
          } else {
            triTexImg[outIdx] = -1;
          }

          final int c3 = outIdx * 3;
          triColors[c3] = vertColors[i0];
          triColors[c3 + 1] = vertColors[i1];
          triColors[c3 + 2] = vertColors[i2];
        }
      }
    }

    if (emittedTris == 0) return;

    // 5. In-place QuickSort on primitive typed arrays (0 allocations, zero boxed objects)
    final Int32List drawOrder = _pool.drawOrder;
    for (int i = 0; i < emittedTris; i++) {
      drawOrder[i] = i;
    }
    _quickSortTriangles(drawOrder, triDepths, 0, emittedTris - 1);

    // 6. Dynamic GPU Batching with non-allocating sublist views
    int cursor = 0;
    final Float32List batchPos = _pool.batchPos;
    final Float32List batchUv = _pool.batchUv;
    final Int32List batchCol = _pool.batchCol;

    while (cursor < emittedTris) {
      final int firstTri = drawOrder[cursor];
      final int batchImgIdx = triTexImg[firstTri];
      int batchEnd = cursor + 1;
      while (batchEnd < emittedTris &&
          triTexImg[drawOrder[batchEnd]] == batchImgIdx) {
        batchEnd++;
      }

      final int batchTris = batchEnd - cursor;

      for (int b = 0; b < batchTris; b++) {
        final int tIdx = drawOrder[cursor + b];
        final int src6 = tIdx * 6;
        final int dst6 = b * 6;
        batchPos[dst6] = triScreenXY[src6];
        batchPos[dst6 + 1] = triScreenXY[src6 + 1];
        batchPos[dst6 + 2] = triScreenXY[src6 + 2];
        batchPos[dst6 + 3] = triScreenXY[src6 + 3];
        batchPos[dst6 + 4] = triScreenXY[src6 + 4];
        batchPos[dst6 + 5] = triScreenXY[src6 + 5];

        if (batchImgIdx >= 0) {
          batchUv[dst6] = triUvXY[src6];
          batchUv[dst6 + 1] = triUvXY[src6 + 1];
          batchUv[dst6 + 2] = triUvXY[src6 + 2];
          batchUv[dst6 + 3] = triUvXY[src6 + 3];
          batchUv[dst6 + 4] = triUvXY[src6 + 4];
          batchUv[dst6 + 5] = triUvXY[src6 + 5];
        }

        final int src3 = tIdx * 3;
        final int dst3 = b * 3;
        batchCol[dst3] = triColors[src3];
        batchCol[dst3 + 1] = triColors[src3 + 1];
        batchCol[dst3 + 2] = triColors[src3 + 2];
      }

      final ui.Vertices vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(batchPos, 0, batchTris * 6),
        textureCoordinates: batchImgIdx >= 0
            ? Float32List.sublistView(batchUv, 0, batchTris * 6)
            : null,
        colors: Int32List.sublistView(batchCol, 0, batchTris * 3),
      );

      if (batchImgIdx >= 0 &&
          textures != null &&
          batchImgIdx < textures!.length &&
          textures![batchImgIdx] != null) {
        canvas.drawVertices(
          vertices,
          BlendMode.modulate,
          _getShaderPaint(textures![batchImgIdx]!),
        );
      } else {
        canvas.drawVertices(
          vertices,
          BlendMode.srcOver,
          _untexturedPaint,
        );
      }

      cursor = batchEnd;
    }
  }

  /// High-performance hybrid QuickSort + InsertionSort on flat typed arrays
  static void _quickSortTriangles(
    Int32List order,
    Float32List depths,
    int low,
    int high,
  ) {
    while (low < high) {
      if (high - low < 16) {
        for (int i = low + 1; i <= high; i++) {
          final int val = order[i];
          final double depth = depths[val];
          int j = i - 1;
          while (j >= low && depths[order[j]] < depth) {
            order[j + 1] = order[j];
            j--;
          }
          order[j + 1] = val;
        }
        break;
      }

      final int mid = (low + high) >> 1;
      final int pivotIdx = order[mid];
      final double pivot = depths[pivotIdx];

      order[mid] = order[high];
      order[high] = pivotIdx;

      int i = low;
      for (int j = low; j < high; j++) {
        if (depths[order[j]] >= pivot) {
          final int tmp = order[i];
          order[i] = order[j];
          order[j] = tmp;
          i++;
        }
      }
      order[high] = order[i];
      order[i] = pivotIdx;

      if (i - low < high - i) {
        _quickSortTriangles(order, depths, low, i - 1);
        low = i + 1;
      } else {
        _quickSortTriangles(order, depths, i + 1, high);
        high = i - 1;
      }
    }
  }

  @override
  bool shouldRepaint(covariant Glb3dPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.orbitYaw != orbitYaw ||
        oldDelegate.orbitPitch != orbitPitch ||
        oldDelegate.zoom != zoom ||
        oldDelegate.model != model ||
        oldDelegate.textures != textures;
  }
}
