#ifndef __CEANIMATION_SH__
#define __CEANIMATION_SH__

#if defined(SKIN_MATRIX_TEXTURE)

#if defined(FLOAT_TEXTURE)
SAMPLER2D(s_BoneMtxMapHighp3, 3);
#define sBoneMtxMap s_BoneMtxMapHighp3
#else
SAMPLER2D(s_BoneMtxMap3, 3);
#define sBoneMtxMap s_BoneMtxMap3
#endif

#if defined(INSTANCED)
    #define cSkinTextureOffset i_data5.xy
    #define cSkinTexelUVSize i_data5.zw
#else
    #define cSkinTextureOffset u_InstanceData3.xy
    #define cSkinTexelUVSize u_InstanceData3.zw
#endif

hfloat RGBAToFloat(hvec4 inValue)
{
    inValue *= 255.0;
    int value = int(inValue.r + 0.5) | (int(inValue.g + 0.5) << 8) | (int(inValue.b + 0.5) << 16) | (int(inValue.a + 0.5) << 24);
    return intBitsToFloat(value);
}

#if defined(FLOAT_TEXTURE)
hmat4 GetMatrxi3x4FromTexture(vec2 uv)
{
    hvec4 col1 = texture2DLod(sBoneMtxMap, uv, 0.0);
    hvec4 col2 = texture2DLod(sBoneMtxMap, vec2(uv.x, uv.y + cSkinTexelUVSize.y), 0.0);
    hvec4 col3 = texture2DLod(sBoneMtxMap, vec2(uv.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0);
    return hmat4_init(
        col1, col2, col3, hvec4_init(0.0, 0.0, 0.0, 1.0)
    );
}
#else
hmat4 GetMatrxi3x4FromTexture(vec2 uv)
{
    hfloat m00 = RGBAToFloat(texture2DLod(sBoneMtxMap, uv, 0.0));
    hfloat m01 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x +       cSkinTexelUVSize.x, uv.y), 0.0));
    hfloat m02 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x + 2.0 * cSkinTexelUVSize.x, uv.y), 0.0));
    hfloat m03 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x + 3.0 * cSkinTexelUVSize.x, uv.y), 0.0));

    hfloat m10 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x,                            uv.y + cSkinTexelUVSize.y), 0.0));
    hfloat m11 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x +       cSkinTexelUVSize.x, uv.y + cSkinTexelUVSize.y), 0.0));
    hfloat m12 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x + 2.0 * cSkinTexelUVSize.x, uv.y + cSkinTexelUVSize.y), 0.0));
    hfloat m13 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x + 3.0 * cSkinTexelUVSize.x, uv.y + cSkinTexelUVSize.y), 0.0));

    hfloat m20 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x,                            uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    hfloat m21 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x +       cSkinTexelUVSize.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    hfloat m22 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x + 2.0 * cSkinTexelUVSize.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    hfloat m23 = RGBAToFloat(texture2DLod(sBoneMtxMap, vec2(uv.x + 3.0 * cSkinTexelUVSize.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    
    return hmat4_init(
        m00, m01, m02, m03,
        m10, m11, m12, m13,
        m20, m21, m22, m23,
        0.0, 0.0, 0.0, 1.0
    );
}
#endif

hmat4 GetBoneTransformFromTexture(int index)
{
#if defined(FLOAT_TEXTURE)
    vec2 uv = vec2(cSkinTextureOffset.x + float(index) * cSkinTexelUVSize.x + 0.5 * cSkinTexelUVSize.x, cSkinTextureOffset.y + 0.5 * cSkinTexelUVSize.y);
#else
    vec2 uv = vec2(cSkinTextureOffset.x + float(index) * 4.0 * cSkinTexelUVSize.x + 0.5 * cSkinTexelUVSize.x, cSkinTextureOffset.y + 0.5 * cSkinTexelUVSize.y);
#endif

    return GetMatrxi3x4FromTexture(uv);
}

hmat4 GetSkinMatrixFromTexture(vec4 blendWeights, vec4 blendIndices)
{
    return GetBoneTransformFromTexture(int(blendIndices.x)) * blendWeights.x +
        GetBoneTransformFromTexture(int(blendIndices.y)) * blendWeights.y +
        GetBoneTransformFromTexture(int(blendIndices.z)) * blendWeights.z +
        GetBoneTransformFromTexture(int(blendIndices.w)) * blendWeights.w;
}

// ---- object velocity：第二 sampler 同 UV 采 prev（仅 Velocity.glsl 定义 VELOCITY_PASS）----
// unit 6 与 samplers.sh 的 u_FogOfWar / u_LightCubeMap 分 stage 共存：本 sampler 仅 VS 使用
// （本文件经 transform.sh 只在 COMPILEVS 下包含），后两者是 COMPILEPS-only，且 velocity 的
// PS 不引用它们、会被 shaderc strip，program 内不发生同 unit 冲突。
// 约束：velocity pass 的 PS 禁止引用任何占用 unit 6 的 PS sampler。
#if defined(VELOCITY_PASS)
#if defined(FLOAT_TEXTURE)
SAMPLER2D(s_PrevBoneMtxMapHighp6, 6);
#define sPrevBoneMtxMap s_PrevBoneMtxMapHighp6
#else
SAMPLER2D(s_PrevBoneMtxMap6, 6);
#define sPrevBoneMtxMap s_PrevBoneMtxMap6
#endif

#if defined(FLOAT_TEXTURE)
hmat4 GetMatrxi3x4FromPrevTexture(vec2 uv)
{
    hvec4 col1 = texture2DLod(sPrevBoneMtxMap, uv, 0.0);
    hvec4 col2 = texture2DLod(sPrevBoneMtxMap, vec2(uv.x, uv.y + cSkinTexelUVSize.y), 0.0);
    hvec4 col3 = texture2DLod(sPrevBoneMtxMap, vec2(uv.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0);
    return hmat4_init(
        col1, col2, col3, hvec4_init(0.0, 0.0, 0.0, 1.0)
    );
}
#else
hmat4 GetMatrxi3x4FromPrevTexture(vec2 uv)
{
    hfloat m00 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, uv, 0.0));
    hfloat m01 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x +       cSkinTexelUVSize.x, uv.y), 0.0));
    hfloat m02 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x + 2.0 * cSkinTexelUVSize.x, uv.y), 0.0));
    hfloat m03 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x + 3.0 * cSkinTexelUVSize.x, uv.y), 0.0));

    hfloat m10 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x,                            uv.y + cSkinTexelUVSize.y), 0.0));
    hfloat m11 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x +       cSkinTexelUVSize.x, uv.y + cSkinTexelUVSize.y), 0.0));
    hfloat m12 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x + 2.0 * cSkinTexelUVSize.x, uv.y + cSkinTexelUVSize.y), 0.0));
    hfloat m13 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x + 3.0 * cSkinTexelUVSize.x, uv.y + cSkinTexelUVSize.y), 0.0));

    hfloat m20 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x,                            uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    hfloat m21 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x +       cSkinTexelUVSize.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    hfloat m22 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x + 2.0 * cSkinTexelUVSize.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));
    hfloat m23 = RGBAToFloat(texture2DLod(sPrevBoneMtxMap, vec2(uv.x + 3.0 * cSkinTexelUVSize.x, uv.y + 2.0 * cSkinTexelUVSize.y), 0.0));

    return hmat4_init(
        m00, m01, m02, m03,
        m10, m11, m12, m13,
        m20, m21, m22, m23,
        0.0, 0.0, 0.0, 1.0
    );
}
#endif

hmat4 GetBoneTransformFromPrevTexture(int index)
{
#if defined(FLOAT_TEXTURE)
    vec2 uv = vec2(cSkinTextureOffset.x + float(index) * cSkinTexelUVSize.x + 0.5 * cSkinTexelUVSize.x, cSkinTextureOffset.y + 0.5 * cSkinTexelUVSize.y);
#else
    vec2 uv = vec2(cSkinTextureOffset.x + float(index) * 4.0 * cSkinTexelUVSize.x + 0.5 * cSkinTexelUVSize.x, cSkinTextureOffset.y + 0.5 * cSkinTexelUVSize.y);
#endif
    return GetMatrxi3x4FromPrevTexture(uv);
}

hmat4 GetSkinMatrixFromPrevTexture(vec4 blendWeights, vec4 blendIndices)
{
    return GetBoneTransformFromPrevTexture(int(blendIndices.x)) * blendWeights.x +
        GetBoneTransformFromPrevTexture(int(blendIndices.y)) * blendWeights.y +
        GetBoneTransformFromPrevTexture(int(blendIndices.z)) * blendWeights.z +
        GetBoneTransformFromPrevTexture(int(blendIndices.w)) * blendWeights.w;
}
#endif // VELOCITY_PASS

#endif

#endif
